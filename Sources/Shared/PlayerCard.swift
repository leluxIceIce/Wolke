// SPDX-License-Identifier: Apache-2.0
import AppKit
import SwiftUI
import WidgetKit

let wolkeOrange = Color(red: 1, green: 85 / 255, blue: 0)
let wolkeInk = Color(red: 22 / 255, green: 21 / 255, blue: 22 / 255)

struct PlayerBackground: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.20, green: 0.13, blue: 0.11), wolkeInk, wolkeInk],
                       startPoint: .bottomLeading, endPoint: .topTrailing)
    }
}

private enum CardArt {
    static let logo = Bundle.main.url(forResource: "SoundCloud", withExtension: "png").flatMap(NSImage.init(contentsOf:))
    static let cat = Bundle.main.url(forResource: "WolkeCat", withExtension: "png").flatMap(NSImage.init(contentsOf:))
}

struct PlayerCard<Controls: View>: View {
    @Environment(\.widgetRenderingMode) private var mode
    let state: PlayerState
    var preview = false
    var family: WidgetFamily = .systemMedium
    @ViewBuilder let controls: () -> Controls

    private var foreground: Color { mode == .fullColor ? .white : .primary }

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                VStack(alignment: .leading, spacing: 3) {
                    header
                    HStack(spacing: 4) {
                        artwork(size: 38)
                        metadata
                    }
                    if let track = state.track {
                        progress(track)
                        controls()
                    }
                }
            case .systemLarge:
                VStack(alignment: .leading, spacing: 6) {
                    header
                    artwork(size: 158)
                        .frame(maxWidth: .infinity)
                    metadata
                    if let track = state.track {
                        progress(track)
                        controls()
                    }
                }
            default:
                HStack(spacing: 9) {
                    artwork(size: 96)
                    VStack(alignment: .leading, spacing: 4) {
                        header
                        metadata
                        if let track = state.track {
                            progress(track)
                            controls()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, family == .systemSmall ? 8 : 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let track = state.track {
                Text(track.title)
                    .font(.system(size: family == .systemLarge ? 18 : 13, weight: .semibold))
                    .lineLimit(family == .systemSmall ? 2 : 1)
                Text(track.artist.isEmpty ? "SoundCloud" : track.artist)
                    .font(.system(size: 10))
                    .foregroundStyle(foreground.opacity(0.68))
                    .lineLimit(1)
            } else {
                Text(state.source == .offline ? "Wolke öffnen" : "Kein Track aktiv")
                    .font(.system(size: 13, weight: .semibold))
                if family != .systemSmall {
                    Text(state.source == .offline ? "Die App verbindet das Widget mit Safari."
                         : "Starte Musik auf SoundCloud in Safari.")
                        .font(.system(size: 11))
                        .foregroundStyle(foreground.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Link(destination: state.track?.url ?? URL(string: "https://soundcloud.com/discover")!) {
                Group {
                    if let logo = CardArt.logo {
                        retainedColor(Image(nsImage: logo).resizable())
                            .scaledToFit()
                            .frame(width: 67, height: 9)
                    } else {
                        Text("SOUNDCLOUD")
                            .font(.system(size: 8, weight: .bold))
                    }
                }
                .foregroundStyle(wolkeInk)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(wolkeOrange, in: RoundedRectangle(cornerRadius: 3))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Auf SoundCloud öffnen")
            Spacer(minLength: 1)
            Circle()
                .fill(state.track?.playing == true ? wolkeOrange : foreground.opacity(0.35))
                .frame(width: 4, height: 4)
                .accessibilityHidden(true)
            if family != .systemSmall {
                Text(state.source == .relay ? "Hintergrund" : state.source.label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(foreground.opacity(0.65))
                    .lineLimit(1)
            }
        }
    }

    private func artwork(size: CGFloat) -> some View {
        let scale = size / 96
        return ZStack(alignment: .topLeading) {
            ZStack {
                Color.white.opacity(0.10)
                if let data = state.cover, let image = NSImage(data: data) {
                    retainedColor(Image(nsImage: image).resizable())
                        .scaledToFill()
                } else {
                    if preview {
                        LinearGradient(colors: [Color(red: 0.17, green: 0.12, blue: 0.12), Color(red: 0.57, green: 0.24, blue: 0.14)],
                                       startPoint: .topTrailing, endPoint: .bottomLeading)
                    }
                    Image(systemName: "waveform")
                        .font(.system(size: max(12, 23 * scale), weight: .medium))
                        .foregroundStyle(wolkeOrange)
                }
            }
            .frame(width: 77 * scale, height: 77 * scale)
            .clipShape(.rect(cornerRadius: 10 * scale))
            .overlay { RoundedRectangle(cornerRadius: 10 * scale).strokeBorder(.white.opacity(0.12)) }
            .offset(x: 9 * scale, y: 9 * scale)
            if let cat = CardArt.cat {
                retainedColor(Image(nsImage: cat).resizable())
                    .scaledToFit()
                    .frame(width: 94 * scale, height: 94 * scale)
                    .offset(y: 6 * scale)
            }
        }
        .frame(width: size, height: 104 * scale)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func retainedColor(_ image: Image) -> some View {
        if #available(macOS 15.0, *) {
            image.widgetAccentedRenderingMode(.fullColor)
        } else {
            image
        }
    }

    private func progress(_ track: Track) -> some View {
        let position = min(track.duration, track.position)
        let start = state.sampledAt.addingTimeInterval(-position)
        let end = start.addingTimeInterval(track.duration)
        return VStack(spacing: 1) {
            Group {
                if track.playing && track.duration > 0 {
                    ProgressView(timerInterval: start...end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                } else {
                    ProgressView(value: position, total: max(1, track.duration))
                }
            }
            .progressViewStyle(.linear)
            .tint(wolkeOrange)
            .frame(height: 6)
            HStack {
                if track.playing && track.duration > 0 {
                    Text(timerInterval: start...end, countsDown: false, showsHours: track.duration >= 3_600)
                } else {
                    Text(format(position))
                }
                Spacer()
                Text(track.duration > 0 ? format(track.duration) : "–:–")
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(foreground.opacity(0.68))
        }
        .padding(.top, 2)
        .accessibilityLabel("Wiedergabefortschritt und Tracklänge")
    }

    private func format(_ time: Double) -> String {
        let seconds = Int(min(max(time, 0), 359_999))
        if seconds >= 3_600 {
            return String(format: "%d:%02d:%02d", seconds / 3_600, seconds / 60 % 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

extension PlayerAction {
    var label: LocalizedStringKey {
        switch self {
        case .toggle: "Wiedergabe umschalten"
        case .back: "15 Sekunden zurück"
        case .forward: "15 Sekunden vor"
        case .like: "Like umschalten"
        case .previous: "Vorheriger Track"
        case .next: "Nächster Track"
        }
    }

    func icon(for track: Track) -> String {
        switch self {
        case .toggle: track.playing ? "pause.fill" : "play.fill"
        case .back: "gobackward.15"
        case .forward: "goforward.15"
        case .like: track.liked ? "heart.fill" : "heart"
        case .previous: "backward.end.fill"
        case .next: "forward.end.fill"
        }
    }

    func enabled(in state: PlayerState) -> Bool {
        guard let track = state.track else { return false }
        guard state.source == .relay || state.source == .safari else { return false }
        switch self {
        case .like: return track.canLike
        case .previous: return track.canPrevious == true
        case .next: return track.canNext == true
        case .back, .forward: return track.duration > 0
        default: return true
        }
    }

    static let playbackControls: [PlayerAction] = [.previous, .back, .toggle, .forward, .next]
    static let controls = playbackControls + [.like]
}

struct PlayerGlyph: View {
    @Environment(\.widgetRenderingMode) private var mode
    var action: PlayerAction? = nil
    let track: Track
    var compact = false

    var body: some View {
        let play = action == .toggle
        let filledPlay = play && mode == .fullColor
        let base = action?.icon(for: track) ?? "text.badge.plus"
        let symbol = filledPlay ? (track.playing ? "pause.circle.fill" : "play.circle.fill") : base
        let accent = filledPlay || (action == .like && track.liked)
        Image(systemName: symbol)
            .symbolRenderingMode(.monochrome)
            .font(.system(size: filledPlay ? (compact ? 21 : 24) : play ? 15 : 12, weight: .semibold))
            .foregroundStyle(accent ? wolkeOrange : mode == .fullColor ? .white : .primary)
            .frame(width: play ? 25 : 19, height: compact ? 22 : 25)
            .contentShape(Rectangle())
    }
}
