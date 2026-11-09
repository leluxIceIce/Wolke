// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import WidgetKit

struct PlayerEntry: TimelineEntry {
    let date: Date
    let state: PlayerState
    var preview = false
}

struct PlayerProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlayerEntry {
        PlayerEntry(date: .now, state: .example, preview: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (PlayerEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            Task { completion(await entry()) }
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PlayerEntry>) -> Void) {
        Task {
            completion(Timeline(entries: [await entry()], policy: .after(.now.addingTimeInterval(300))))
        }
    }

    private func entry() async -> PlayerEntry {
        let state: PlayerState? = await LocalClient.request("state", timeout: 2)
        return PlayerEntry(date: .now, state: state ?? .offline)
    }
}

private struct PlayerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PlayerEntry

    var body: some View {
        PlayerCard(state: entry.state, preview: entry.preview, family: family) {
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
        StaticConfiguration(kind: "WolkePlayer", provider: PlayerProvider()) { entry in
            PlayerWidgetView(entry: entry)
        }
        .configurationDisplayName("Wolke")
        .description("Cover, Wiedergabe, Trackwechsel, Likes und Playlists für SoundCloud.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
