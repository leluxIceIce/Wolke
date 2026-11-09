// SPDX-License-Identifier: Apache-2.0
import Foundation

enum PlayerAction: String, Codable, CaseIterable, Sendable {
    case toggle, back, forward, like, previous, next
}

struct Track: Codable, Equatable, Sendable {
    let url: URL
    let title: String
    let artist: String
    let artwork: URL?
    var duration: Double
    var position: Double
    var playing: Bool
    var liked: Bool
    var canLike: Bool
    var canPrevious: Bool?
    var canNext: Bool?

    var playlistLink: URL {
        var components = URLComponents()
        components.scheme = "wolke"
        components.host = "playlist"
        components.queryItems = [URLQueryItem(name: "track", value: url.absoluteString)]
        return components.url!
    }

    var isValid: Bool {
        url.scheme == "https" && url.host == "soundcloud.com"
            && url.user == nil && url.password == nil && url.port == nil
            && url.query == nil && url.fragment == nil && url.pathComponents.count == 3
            && title.count <= 1_000 && artist.count <= 1_000
            && duration.isFinite && position.isFinite && duration >= 0 && position >= 0
    }

    var coverURL: URL? {
        guard let artwork, artwork.scheme == "https", let host = artwork.host,
              host == "sndcdn.com" || host.hasSuffix(".sndcdn.com"),
              artwork.user == nil, artwork.password == nil, artwork.port == nil
        else { return nil }
        return artwork
    }

    static let example = Track(
        url: URL(string: "https://soundcloud.com/forss/flickermood")!,
        title: "Flickermood", artist: "Forss", artwork: nil, duration: 213,
        position: 112, playing: false, liked: true, canLike: true, canPrevious: true, canNext: true
    )
}

enum PlayerSource: String, Codable, Sendable {
    case safari, relay, loading, failed, idle, offline

    var label: String {
        switch self {
        case .safari: "Safari"
        case .relay: "Safari · Hintergrund"
        case .loading: "Übernahme …"
        case .failed: "Safari öffnen"
        case .idle: "Bereit"
        case .offline: "Wolke öffnen"
        }
    }
}

struct PlayerState: Codable, Sendable {
    var track: Track?
    var source: PlayerSource
    var sampledAt = Date()
    var cover: Data?
    var widgetToken: UUID?

    func widgetControlURL(_ action: PlayerAction) -> URL? {
        guard let track, let widgetToken else { return nil }
        var components = URLComponents()
        components.scheme = "wolke"
        components.host = "control"
        components.queryItems = [
            URLQueryItem(name: "action", value: action.rawValue),
            URLQueryItem(name: "track", value: track.url.absoluteString),
            URLQueryItem(name: "token", value: widgetToken.uuidString)
        ]
        return components.url
    }

    func position(at now: Date = .now) -> Double {
        guard let track else { return 0 }
        let elapsed = track.playing ? max(0, now.timeIntervalSince(sampledAt)) : 0
        return max(0, min(track.duration, track.position + elapsed))
    }

    static let offline = PlayerState(source: .offline)
    static let example = PlayerState(track: .example, source: .safari)
}

struct PlayerCommand: Codable, Sendable {
    let id: UUID
    let action: PlayerAction
    let url: URL
}

struct SafariPacket: Codable, Sendable {
    let tab: Int
    var profile: String?
    var track: Track?
    var ack: UUID?
    var closed: Bool?
    var claim: UUID?
    var ping: Bool?
}

struct SafariResume: Codable, Sendable {
    let id: UUID
    let url: URL
    let position: Double
}

struct SafariReply: Codable, Sendable {
    var command: PlayerCommand?
    var resume: SafariResume?
    var connected: Bool?
    var playlist: URL?
}

struct ActionRequest: Codable, Sendable {
    let action: PlayerAction
    let url: URL?
}
