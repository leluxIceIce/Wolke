// SPDX-License-Identifier: Apache-2.0
import Foundation
import Network

@MainActor
final class LocalServer {
    private let queue = DispatchQueue(label: "studio.local.wolke.bridge")
    private var listener: NWListener?
    private var connections: [UUID: HTTPConnection] = [:]
    private let route: (String, String, Data) async -> Data?
    var onFailure: (() -> Void)?

    init(route: @escaping (String, String, Data) async -> Data?) {
        self.route = route
    }

    func start() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .init(rawValue: LocalClient.port)!)
        let listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                Task { @MainActor in self?.onFailure?() }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                guard let self, self.connections.count < 32 else {
                    connection.cancel()
                    return
                }
                let id = UUID()
                let request = HTTPConnection(connection: connection, queue: self.queue) { [weak self] in
                    self?.connections[id] = nil
                }
                self.connections[id] = request
                request.start(route: self.route)
            }
        }
        self.listener = listener
        listener.start(queue: queue)
    }
}

@MainActor
private final class HTTPConnection {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let onClose: () -> Void
    private var received = Data()
    private var timeout: Task<Void, Never>?
    private var closed = false

    init(connection: NWConnection, queue: DispatchQueue, onClose: @escaping () -> Void) {
        self.connection = connection
        self.queue = queue
        self.onClose = onClose
    }

    func start(route: @escaping (String, String, Data) async -> Data?) {
        connection.start(queue: queue)
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(7))
            guard !Task.isCancelled else { return }
            self?.close()
        }
        receive(route: route)
    }

    private func receive(route: @escaping (String, String, Data) async -> Data?) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, !self.closed else { return }
                if let data { self.received.append(data) }
                guard error == nil, self.received.count <= 32_768 else { return self.close() }
                let marker = Data([13, 10, 13, 10])
                guard let end = self.received.range(of: marker) else {
                    return complete ? self.close() : self.receive(route: route)
                }
                guard let header = String(data: self.received[..<end.lowerBound], encoding: .utf8) else {
                    return self.close()
                }
                let lines = header.components(separatedBy: "\r\n")
                let request = lines[0].split(separator: " ")
                guard request.count == 3 else { return self.close() }
                let headers = lines.dropFirst().reduce(into: [String: String]()) { result, line in
                    guard let colon = line.firstIndex(of: ":") else { return }
                    result[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                }
                guard headers["authorization"] == LocalClient.authorization else {
                    return self.respond(code: "403 Forbidden")
                }
                guard headers["transfer-encoding"] == nil,
                      let length = Int(headers["content-length"] ?? "0"), (0...16_384).contains(length)
                else { return self.close() }
                guard self.received.count >= end.upperBound + length else {
                    return complete ? self.close() : self.receive(route: route)
                }
                let body = Data(self.received[end.upperBound ..< end.upperBound + length])
                if let response = await route(String(request[0]), String(request[1]), body) {
                    self.respond(code: "200 OK", body: response)
                } else {
                    self.respond(code: "400 Bad Request")
                }
            }
        }
    }

    private func respond(code: String, body: Data = Data()) {
        guard !closed else { return }
        var response = Data("HTTP/1.1 \(code)\r\nContent-Type: application/json\r\nCache-Control: no-store\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { [weak self] _ in
            Task { @MainActor in self?.close() }
        })
    }

    private func close() {
        guard !closed else { return }
        closed = true
        timeout?.cancel()
        connection.cancel()
        onClose()
    }
}
