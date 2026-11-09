// SPDX-License-Identifier: Apache-2.0
import AppKit
import ImageIO
import SafariServices
import UniformTypeIdentifiers
import WidgetKit

enum SafariConnection {
    case checking, unavailable, disabled, waitingForTab, connected

    var label: String {
        switch self {
        case .checking: "Safari-Erweiterung wird geprüft …"
        case .unavailable: "Safari meldet die Erweiterung als nicht verfügbar."
        case .disabled: "Wolke ist in Safari noch deaktiviert."
        case .waitingForTab: "Erweiterung aktiv · wartet auf einen SoundCloud-Tab"
        case .connected: "SoundCloud-Tab mit Wolke verbunden"
        }
    }
}

@MainActor
final class Controller: ObservableObject {
    @Published private(set) var state = PlayerState(source: .idle)
    @Published private(set) var bridgeFailed = false
    @Published private(set) var safariConnection = SafariConnection.checking
    private let widgetToken = UUID()
    static let safariExtensionID = "studio.local.wolke.Safari"

    private struct Tab: Hashable {
        let profile: String?
        let id: Int
    }

    private struct Report {
        let track: Track
        let time: Date
        let started: Date
    }

    private struct Pending {
        let command: PlayerCommand
        let tab: Tab
        let complete: CheckedContinuation<Void, Never>
        var sent = false
    }

    private struct Transfer {
        let original: Tab
        let resume: SafariResume
        var destination: Tab?
    }

    private struct PlaylistOpening {
        let id: UUID
        let track: URL
        let expires: Date
    }

    private var playlistOpening: PlaylistOpening?
    private var safari: [Tab: Report] = [:]
    private var selectedTab: Tab?
    private var pending: [Pending] = []
    private var transfer: Transfer?
    private var handoffTimeout: Task<Void, Never>?
    private var relayTab: Tab?
    private var coverJob: Task<Void, Never>?
    private var coverURL: URL?
    private var server: LocalServer?

    func start() {
        let server = LocalServer { [weak self] method, path, body in
            guard let self else { return nil }
            let decoder = JSONDecoder()
            let encoder = JSONEncoder()
            switch (method, path) {
            case ("GET", "/state"):
                var widgetState = state
                widgetState.widgetToken = widgetToken
                return try? encoder.encode(widgetState)
            case ("POST", "/safari"):
                guard let packet = try? decoder.decode(SafariPacket.self, from: body) else { return nil }
                return try? encoder.encode(receive(packet))
            case ("POST", "/action"):
                guard let request = try? decoder.decode(ActionRequest.self, from: body) else { return nil }
                await perform(request.action, expectedURL: request.url)
                return try? encoder.encode(state)
            default:
                return nil
            }
        }
        server.onFailure = { [weak self] in self?.bridgeFailed = true }
        self.server = server
        do { try server.start() } catch { bridgeFailed = true }
    }

    func checkSafariExtension() {
        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: Self.safariExtensionID) { [weak self] state, _ in
            let enabled = state?.isEnabled
            Task { @MainActor in
                guard let self, self.safariConnection != .connected else { return }
                switch enabled {
                case true?: self.safariConnection = .waitingForTab
                case false?: self.safariConnection = .disabled
                case nil: self.safariConnection = .unavailable
                }
            }
        }
    }

    func safariQuit() {
        safariConnection = .checking
        safari.removeAll()
        relayTab = nil
        selectedTab = nil
        cancelTransfer()
        if var track = state.track {
            track.position = state.position()
            track.playing = false
            track.canLike = false
            set(track, source: .failed)
        }
    }

    func widgetCommand(for url: URL) -> ActionRequest? {
        guard url.scheme == "wolke", url.host == "control",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let token = items.first(where: { $0.name == "token" })?.value,
              UUID(uuidString: token) == widgetToken,
              let name = items.first(where: { $0.name == "action" })?.value,
              let action = PlayerAction(rawValue: name), action.enabled(in: state),
              let track = state.track,
              items.first(where: { $0.name == "track" })?.value == track.url.absoluteString
        else { return nil }
        return ActionRequest(action: action, url: track.url)
    }

    func playlistURL(for url: URL) -> URL? {
        guard state.track?.url == url, state.track?.isValid == true,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        let id = UUID()
        playlistOpening = PlaylistOpening(id: id, track: url, expires: .now.addingTimeInterval(45))
        components.fragment = "wolke-playlist=\(id.uuidString)"
        return components.url
    }

    private func receive(_ packet: SafariPacket) -> SafariReply {
        let tab = Tab(profile: packet.profile, id: packet.tab)
        if packet.ping == true || packet.track?.isValid == true {
            if safariConnection != .connected { safariConnection = .connected }
            if packet.ping == true { return SafariReply(connected: true) }
        }
        if let ack = packet.ack, let index = pending.firstIndex(where: { $0.command.id == ack && $0.tab == tab }) {
            pending.remove(at: index).complete.resume()
        }
        if let claim = packet.claim {
            if let opening = playlistOpening, opening.id == claim {
                playlistOpening = nil
                guard opening.expires > .now else { return SafariReply() }
                return SafariReply(playlist: opening.track)
            }
            guard var transfer, transfer.resume.id == claim, transfer.original.profile == tab.profile,
                  transfer.original != tab, transfer.destination == nil
            else { return SafariReply() }
            transfer.destination = tab
            self.transfer = transfer
            relayTab = tab
            return SafariReply(resume: transfer.resume)
        }
        if packet.closed == true || packet.track == nil {
            return SafariReply(resume: detach(tab, allowTransfer: packet.closed == true))
        }
        guard let track = packet.track, track.isValid else { return SafariReply() }
        let prior = safari[tab]
        let began = track.playing && (prior?.track.playing != true || prior?.track.url != track.url)
        let now = Date()
        safari = safari.filter { now.timeIntervalSince($0.value.time) < 180 || $0.key == selectedTab }
        safari[tab] = Report(track: track, time: now, started: began ? now : prior?.started ?? now)

        if began && selectedTab != tab {
            cancelTransfer()
            selectedTab = tab
        }
        if selectedTab == tab {
            set(track, source: tab == relayTab ? .relay : .safari, at: now)
        }
        if let next = pending.firstIndex(where: { $0.tab == tab && !$0.sent }) {
            pending[next].sent = true
            return SafariReply(command: pending[next].command)
        }
        return SafariReply()
    }

    private func detach(_ tab: Tab, allowTransfer: Bool) -> SafariResume? {
        safari[tab] = nil
        let wasRelay = relayTab == tab
        if wasRelay { relayTab = nil }
        guard tab == selectedTab, var track = state.track else { return nil }
        let now = Date()
        selectedTab = nil
        if let other = safari.filter({ $0.value.track.playing && now.timeIntervalSince($0.value.time) < 4 })
            .max(by: { $0.value.started < $1.value.started }) {
            selectedTab = other.key
            set(other.value.track, source: other.key == relayTab ? .relay : .safari, at: other.value.time)
            return nil
        }

        let position = state.position(at: now)
        let shouldResume = track.playing && (track.duration == 0 || position < track.duration - 0.5)
        track.position = position
        track.playing = false
        track.canLike = false
        guard allowTransfer, !wasRelay, shouldResume else {
            set(track, source: .failed)
            return nil
        }

        let resume = SafariResume(id: UUID(), url: track.url, position: position)
        transfer = Transfer(original: tab, resume: resume)
        set(track, source: .loading)
        handoffTimeout = Task {
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            cancelTransfer()
            set(track, source: .failed)
        }
        return resume
    }

    private func cancelTransfer() {
        handoffTimeout?.cancel()
        handoffTimeout = nil
        transfer = nil
    }

    func perform(_ action: PlayerAction, expectedURL: URL?) async {
        guard let track = state.track, expectedURL == track.url, let tab = selectedTab,
              state.source == .safari || state.source == .relay else { return }
        let command = PlayerCommand(id: UUID(), action: action, url: track.url)
        await withCheckedContinuation { continuation in
            pending.append(Pending(command: command, tab: tab, complete: continuation))
            Task {
                try? await Task.sleep(for: .seconds(3))
                if let index = pending.firstIndex(where: { $0.command.id == command.id }) {
                    pending.remove(at: index).complete.resume()
                }
            }
        }
    }

    private func set(_ track: Track, source: PlayerSource, at time: Date = .now) {
        let previous = state
        let newCoverURL = track.coverURL
        let keepCover = coverURL == newCoverURL
        state = PlayerState(track: track, source: source, sampledAt: time, cover: keepCover ? previous.cover : nil)
        if previous.track?.url != track.url || previous.source != source
            || previous.track?.playing != track.playing || previous.track?.liked != track.liked
            || previous.track?.duration != track.duration || previous.track?.canLike != track.canLike
            || previous.track?.canPrevious != track.canPrevious || previous.track?.canNext != track.canNext
            || previous.track?.title != track.title || previous.track?.artist != track.artist
            || abs(previous.position(at: time) - track.position) > 2 {
            refreshWidget()
        }

        guard !keepCover else { return }
        coverURL = newCoverURL
        coverJob?.cancel()
        guard let url = newCoverURL else { return }
        coverJob = Task {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200, data.count < 1_500_000,
                  !Task.isCancelled, coverURL == url,
                  let image = CGImageSourceCreateWithData(data as CFData, nil),
                  let resized = CGImageSourceCreateThumbnailAtIndex(image, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 224,
                    kCGImageSourceCreateThumbnailWithTransform: true
                  ] as CFDictionary)
            else { return }
            let buffer = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(buffer, UTType.jpeg.identifier as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(destination, resized, [kCGImageDestinationLossyCompressionQuality: 0.84] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return }
            state.cover = buffer as Data
            refreshWidget()
        }
    }

    private func refreshWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: "WolkePlayer")
    }
}
