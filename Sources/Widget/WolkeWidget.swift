// SPDX-License-Identifier: Apache-2.0
import AppIntents
import OSLog
import SwiftUI
import WidgetKit

enum WidgetMascot: String, CaseIterable {
    case cat, bunny, plagueDoctor, mummy, snail, none

    var title: LocalizedStringResource {
        switch self {
        case .cat: "Schlafende Katze"
        case .bunny: "Picknick-Hase"
        case .plagueDoctor: "Pestarzt & Krähe"
        case .mummy: "Mumie"
        case .snail: "Hexenturm-Schnecke"
        case .none: "Ohne Figur"
        }
    }

    var art: PlayerMascot {
        switch self {
        case .cat: .cat
        case .bunny: .illustration(front: "PicnicBunny", behind: "PicnicCorn")
        case .plagueDoctor: .illustration(front: "PlagueDoctor")
        case .mummy: .illustration(front: "Mummy")
        case .snail: .illustration(front: "TowerSnail")
        case .none: .none
        }
    }
}

struct MascotOptions: DynamicOptionsProvider {
    func results() async -> IntentItemCollection<String> {
        let items = WidgetMascot.allCases.map { IntentItem($0.rawValue, title: $0.title) }
        return IntentItemCollection(sections: [IntentItemSection(items: items)])
    }

    func defaultResult() async -> String? { WidgetMascot.cat.rawValue }
}

struct PlayerConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Wolke bearbeiten"

    // A primitive value avoids AppEnum resolution by Link services, which
    // cannot identify the developer team of an ad hoc signed extension.
    @Parameter(title: "Figur", optionsProvider: MascotOptions())
    var mascot: String?

    var selectedMascot: WidgetMascot {
        mascot.flatMap(WidgetMascot.init(rawValue:)) ?? .cat
    }
}

struct PlayerEntry: TimelineEntry {
    let date: Date
    let state: PlayerState
    var mascot: WidgetMascot = .cat
    var preview = false
}

struct PlayerProvider: AppIntentTimelineProvider {
    private let logger = Logger(subsystem: "studio.local.wolke", category: "widget-configuration")

    func placeholder(in context: Context) -> PlayerEntry {
        PlayerEntry(date: .now, state: .example, preview: true)
    }

    func snapshot(for configuration: PlayerConfiguration, in context: Context) async -> PlayerEntry {
        if context.isPreview {
            return PlayerEntry(date: .now, state: .example, mascot: configuration.selectedMascot, preview: true)
        }
        return await entry(mascot: configuration.selectedMascot)
    }

    func timeline(for configuration: PlayerConfiguration, in context: Context) async -> Timeline<PlayerEntry> {
        let mascot = configuration.selectedMascot
        logger.info("Rendering mascot: \(mascot.rawValue, privacy: .public)")
        return Timeline(entries: [await entry(mascot: mascot)], policy: .after(.now.addingTimeInterval(300)))
    }

    private func entry(mascot: WidgetMascot) async -> PlayerEntry {
        let state: PlayerState? = await LocalClient.request("state", timeout: 2)
        return PlayerEntry(date: .now, state: state ?? .offline, mascot: mascot)
    }
}

private struct PlayerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PlayerEntry

    var body: some View {
        PlayerCard(state: entry.state, preview: entry.preview, family: family, mascot: entry.mascot.art) {
            if let track = entry.state.track {
                if family == .systemSmall {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 1) {
                            ForEach(PlayerAction.playbackControls, id: \.self) { action in
                                control(action, track: track)
                            }
                        }
                        HStack(spacing: 4) {
                            control(.like, track: track)
                            playlist(track)
                        }
                    }
                } else {
                    HStack(spacing: 1) {
                        ForEach(PlayerAction.controls, id: \.self) { action in
                            control(action, track: track)
                        }
                        playlist(track)
                    }
                }
            }
        }
        .containerBackground(for: .widget) { PlayerBackground() }
        .widgetURL(fallbackURL)
    }

    private var fallbackURL: URL? {
        if entry.state.source == .failed { return URL(string: "wolke://player") }
        if entry.state.track == nil { return URL(string: "wolke://open") }
        return nil
    }

    @ViewBuilder private func control(_ action: PlayerAction, track: Track) -> some View {
        if action.enabled(in: entry.state), let url = entry.state.widgetControlURL(action) {
            Link(destination: url) { controlLabel(action, track: track) }
                .buttonStyle(.plain)
                .accessibilityLabel(action.label)
        } else {
            controlLabel(action, track: track)
                .opacity(action.enabled(in: entry.state) ? 1 : 0.38)
                .accessibilityHidden(true)
        }
    }

    private func controlLabel(_ action: PlayerAction?, track: Track) -> some View {
        PlayerGlyph(action: action, track: track, compact: family == .systemSmall)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
    }

    private func playlist(_ track: Track) -> some View {
        Link(destination: track.playlistLink) { controlLabel(nil, track: track) }
            .buttonStyle(.plain)
            .accessibilityLabel("Zu Playlist hinzufügen")
    }
}

@main
struct WolkeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "WolkePlayer", intent: PlayerConfiguration.self, provider: PlayerProvider()) { entry in
            PlayerWidgetView(entry: entry)
        }
        .configurationDisplayName("Wolke")
        .description("Cover, Wiedergabe, Trackwechsel, Likes und Playlists für SoundCloud.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
