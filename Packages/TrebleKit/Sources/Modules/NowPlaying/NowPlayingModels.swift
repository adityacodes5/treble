import Foundation
import MediaService
import Observation
import TrebleCore

/// What the menu bar item shows while music is playing.
enum TickerStyle: String, CaseIterable, Identifiable {
    case titleArtist
    case title
    case artistTitle
    case iconOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .titleArtist: "Song — Artist"
        case .title: "Song"
        case .artistTitle: "Artist — Song"
        case .iconOnly: "Icon only"
        }
    }
}

@MainActor
@Observable
final class NowPlayingPreferences {
    var tickerStyle: TickerStyle { didSet { save(tickerStyle.rawValue, "tickerStyle") } }
    /// The widest the menu bar text may get, in points.
    var maxWidth: Double { didSet { save(maxWidth, "maxWidth") } }
    /// Grey out the menu bar text while paused.
    var dimWhenPaused: Bool { didSet { save(dimWhenPaused, "dimWhenPaused") } }
    /// Remove the menu bar item entirely when no music app has a track loaded.
    var hideWhenIdle: Bool { didSet { save(hideWhenIdle, "hideWhenIdle") } }

    static let widthChoices: [Double] = [120, 160, 220, 300]

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let settings: ModuleSettings?

    /// Pass nil (in tests) to use the defaults without saving anything.
    init(settings: ModuleSettings?) {
        self.settings = settings
        tickerStyle = settings.flatMap { TickerStyle(rawValue: $0.value("tickerStyle", default: "")) } ?? .titleArtist
        maxWidth = settings?.value("maxWidth", default: 160.0) ?? 160
        dimWhenPaused = settings?.value("dimWhenPaused", default: true) ?? true
        hideWhenIdle = settings?.value("hideWhenIdle", default: false) ?? false
    }

    private func save(_ value: Any, _ name: String) {
        settings?.set(value, for: name)
        onChange?()
    }
}

/// Decides what the menu bar item shows. Pure, so it can be tested.
enum Ticker {
    static let symbol = "music.note"
    /// After this long paused, the text gives way to just the icon.
    static let pausedCollapseDelay: TimeInterval = 5 * 60

    static func label(
        for nowPlaying: NowPlaying?,
        style: TickerStyle,
        maxWidth: Double,
        dimWhenPaused: Bool,
        hideWhenIdle: Bool,
        pausedFor: TimeInterval
    ) -> MenuBarLabel {
        guard let nowPlaying else {
            return MenuBarLabel(symbol: symbol, isDimmed: true, isHidden: hideWhenIdle, toolTip: "Nothing playing")
        }
        let toolTip = [nowPlaying.title, nowPlaying.artist, nowPlaying.album]
            .compactMap { $0 }
            .joined(separator: " — ")
        let paused = !nowPlaying.isPlaying
        let collapsed = paused && pausedFor >= pausedCollapseDelay

        guard style != .iconOnly, !collapsed else {
            return MenuBarLabel(symbol: symbol, isDimmed: paused && dimWhenPaused, toolTip: toolTip)
        }
        return MenuBarLabel(
            text: text(for: nowPlaying, style: style),
            maxWidth: maxWidth,
            isDimmed: paused && dimWhenPaused,
            toolTip: toolTip
        )
    }

    static func text(for nowPlaying: NowPlaying, style: TickerStyle) -> String {
        let title = nowPlaying.title
        guard let artist = nowPlaying.artist else { return title }
        switch style {
        case .titleArtist: return "\(title) — \(artist)"
        case .artistTitle: return "\(artist) — \(title)"
        case .title, .iconOnly: return title
        }
    }

    /// "3:07", or "1:02:45" for long tracks.
    static func time(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
