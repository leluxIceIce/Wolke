// SPDX-License-Identifier: Apache-2.0
import Foundation

enum LocalClient {
    static let port: UInt16 = 48_768
    static let authorization = "Bearer " + LocalKey.value

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.connectionProxyDictionary = [:]
        return URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }()

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    static func request<Response: Decodable>(
        _ path: String, body: Data? = nil, timeout: TimeInterval = 5
    ) async -> Response? {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/\(path)")!)
        request.timeoutInterval = timeout
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        if let body {
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            return nil
        }
    }
}
