import MediaService
import SwiftUI
import TrebleCore

/// Now Playing: the song in your menu bar; click for album art and controls.
///
/// Works with Spotify and Apple Music. Showing the song needs no permission;
/// play/pause/skip asks once to control the app (a standard macOS prompt).
public final class NowPlayingModule: TrebleModule {
    public static let id = "nowPlaying"
    public static let name = "Now Playing"
    public static let summary = "The song in your menu bar, with album art and controls"
    public static let symbol = "music.note"
    public static let defaultPlacement: Placement = .both
    public static let tileSize: TileSize = .wide

    private let context: ModuleContext
    private let preferences: NowPlayingPreferences
    private let media = MediaService.shared
    /// When playback was last paused, for collapsing the ticker after a while.
    private var pausedSince: Date?
    private var collapseTimer: Cancellation?

    public init(context: ModuleContext) {
        self.context = context
        preferences = NowPlayingPreferences(settings: context.settings)
    }

    public func start() {
        // Treble cancels this when the feature is turned off; MediaService
        // stops listening entirely once nobody is subscribed.
        context.own(media.subscribe { [weak self] _ in self?.mediaChanged() })
        preferences.onChange = { [weak self] in self?.updateMenuBar() }
        mediaChanged()
    }

    public func stop() {
        preferences.onChange = nil
        collapseTimer?.cancel()
        collapseTimer = nil
    }

    public var tile: AnyView? {
        AnyView(NowPlayingTile(media: media))
    }

    public var menuBarPopover: AnyView? {
        AnyView(NowPlayingPopover(media: media, accessory: context.slotView(.nowPlayingAccessory)))
    }

    public var settingsView: AnyView? {
        AnyView(NowPlayingSettings(preferences: preferences, media: media))
    }

    /// Middle-click the song to play or pause.
    public func handleMenuBarClick(_ click: MenuBarClick) -> Bool {
        guard media.nowPlaying != nil else { return false }
        Task { await media.send(.playPause) }
        return true
    }

    // MARK: Menu bar

    private func mediaChanged() {
        let paused = media.nowPlaying.map { !$0.isPlaying } ?? false
        if paused {
            if pausedSince == nil { pausedSince = Date() }
        } else {
            pausedSince = nil
        }
        updateMenuBar()
    }

    private func updateMenuBar() {
        let pausedFor = pausedSince.map { Date().timeIntervalSince($0) } ?? 0
        context.setMenuBarLabel(Ticker.label(
            for: media.nowPlaying,
            style: preferences.tickerStyle,
            maxWidth: preferences.maxWidth,
            dimWhenPaused: preferences.dimWhenPaused,
            hideWhenIdle: preferences.hideWhenIdle,
            pausedFor: pausedFor
        ))

        // One timer, only while paused, to shrink the ticker to an icon later.
        collapseTimer?.cancel()
        collapseTimer = nil
        if let pausedSince, pausedFor < Ticker.pausedCollapseDelay {
            // Not handed to `context.own`, since it's replaced often; `stop()` cancels it.
            collapseTimer = TrebleTimer.once(
                at: pausedSince.addingTimeInterval(Ticker.pausedCollapseDelay),
                tolerance: 10
            ) { [weak self] in
                self?.updateMenuBar()
            }
        }
    }
}
