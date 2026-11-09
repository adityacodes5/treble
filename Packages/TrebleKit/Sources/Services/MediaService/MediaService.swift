import AppKit
import Observation
import TrebleCore

/// Treble's single doorway to "what's playing": Spotify and Apple Music today.
///
/// Event-driven: it listens to the apps' own broadcasts and never polls.
/// Nothing runs until a feature subscribes, and everything stops when the
/// last one unsubscribes. SwiftUI views can observe it directly.
@MainActor
@Observable
public final class MediaService {
    public static let shared = MediaService()

    /// What's playing now, from whichever app most recently started playing.
    public private(set) var nowPlaying: NowPlaying?
    /// Album art for `nowPlaying`, once it has loaded.
    public private(set) var artwork: NSImage?
    /// Whether Treble may control each app (needed for play/pause/skip).
    public private(set) var access: [MediaSourceID: ControlAccess] = [:]

    @ObservationIgnored private var states: [MediaSourceID: NowPlaying] = [:]
    @ObservationIgnored private var startedPlaying: [MediaSourceID: Date] = [:]
    @ObservationIgnored private var subscribers: [UUID: @MainActor (NowPlaying?) -> Void] = [:]
    @ObservationIgnored private var observers: [Cancellation] = []
    @ObservationIgnored private var artworkKey: String?
    @ObservationIgnored private var artworkIsFullSize = false
    @ObservationIgnored private var artworkTask: Task<Void, Never>?

    init() {}

    /// Music apps installed on this Mac.
    public var installedSources: [MediaSourceID] {
        MediaSourceID.allCases.filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil
        }
    }

    // MARK: Subscribing

    /// Starts listening (if nobody was already) and calls `onChange` whenever
    /// what's on screen should change. Cancel to stop.
    public func subscribe(_ onChange: (@MainActor (NowPlaying?) -> Void)? = nil) -> Cancellation {
        let id = UUID()
        subscribers[id] = onChange ?? { _ in }
        if subscribers.count == 1 {
            startListening()
        }
        return Cancellation { [weak self] in
            guard let self else { return }
            subscribers[id] = nil
            if subscribers.isEmpty {
                stopListening()
            }
        }
    }

    public var isListening: Bool { !observers.isEmpty }

    private func startListening() {
        let distributed = DistributedNotificationCenter.default()
        for source in MediaSourceID.allCases {
            observers.append(distributed.trebleObserve(PlayerNotifications.name(for: source)) { [weak self] note in
                self?.received(note.userInfo ?? [:], from: source)
            })
        }

        // An app quitting takes its track with it.
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.trebleObserve(NSWorkspace.didTerminateApplicationNotification) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let source = MediaSourceID.allCases.first(where: { $0.bundleID == app.bundleIdentifier }) else { return }
            self?.update(source, to: nil)
        })

        // If an app was already playing before Treble started, there's no
        // broadcast to catch, so ask it once (only if already allowed: never a surprise prompt).
        Task { await loadInitialState() }
    }

    private func stopListening() {
        observers.forEach { $0.cancel() }
        observers.removeAll()
        artworkTask?.cancel()
        states.removeAll()
        startedPlaying.removeAll()
        nowPlaying = nil
        artwork = nil
        artworkKey = nil
    }

    private func loadInitialState() async {
        await refreshAccess()
        for source in MediaSourceID.allCases where access[source] == .granted && isListening && states[source] == nil {
            if let state = PlayerScripts.currentState(of: source, at: Date()) {
                update(source, to: state)
            }
        }
    }

    // MARK: Updates

    private func received(_ info: [AnyHashable: Any], from source: MediaSourceID) {
        let now = Date()
        let incoming = PlayerNotifications.parse(info, from: source, at: now)
        update(source, to: incoming.map { NowPlayingLogic.merge(previous: states[source], incoming: $0, at: now) })
    }

    private func update(_ source: MediaSourceID, to state: NowPlaying?) {
        let wasPlaying = states[source]?.isPlaying ?? false
        states[source] = state
        if let state, state.isPlaying, !wasPlaying {
            startedPlaying[source] = Date()
        }
        if state == nil {
            startedPlaying[source] = nil
        }
        publish(NowPlayingLogic.pick(states: states, startedPlaying: startedPlaying))
    }

    private func publish(_ next: NowPlaying?) {
        let previous = nowPlaying
        nowPlaying = next
        loadArtworkIfNeeded()

        // Tell subscribers only when something visible changed.
        switch (previous, next) {
        case (nil, nil):
            return
        case let (old?, new?) where old.looksTheSame(as: new, at: Date()):
            return
        default:
            for subscriber in subscribers.values {
                subscriber(next)
            }
        }
    }

    // MARK: Controls

    /// Sends a command to the app that's playing. Asks for permission the
    /// first time (macOS shows its own prompt).
    public func send(_ command: MediaCommand) async {
        guard let current = nowPlaying else { return }
        let source = current.source
        let granted = await ensureAccess(for: source)
        guard granted, PlayerScripts.send(command, to: source) else { return }

        // Show the result straight away; the app's own broadcast confirms it shortly.
        var optimistic = current
        let now = Date()
        switch command {
        case .playPause, .play, .pause:
            let playing = command == .play || (command == .playPause && !current.isPlaying)
            optimistic.position = current.elapsed(at: now)
            optimistic.positionDate = now
            optimistic.isPlaying = playing
        case .seek(let seconds):
            optimistic.position = seconds
            optimistic.positionDate = now
        case .next, .previous:
            // The app's broadcast brings the new track. "Previous" may instead
            // restart the same one, which Music doesn't broadcast, so re-read position.
            try? await Task.sleep(for: .milliseconds(400))
            refreshPosition()
            return
        }
        update(source, to: optimistic)
    }

    /// Asks the app for its exact position, to correct any drift. Cheap; call
    /// when a progress bar becomes visible. Does nothing without permission.
    public func refreshPosition() {
        guard var current = nowPlaying, access[current.source] == .granted,
              let position = PlayerScripts.position(of: current.source) else { return }
        current.position = position
        current.positionDate = Date()
        states[current.source] = current
        nowPlaying = current
    }

    /// Re-checks permissions without prompting.
    public func refreshAccess() async {
        for source in installedSources {
            access[source] = await AppleScripting.access(for: source.bundleID, ask: false)
        }
    }

    /// Shows macOS's permission prompt for `source` if the user hasn't decided.
    @discardableResult
    public func ensureAccess(for source: MediaSourceID) async -> Bool {
        var result = await AppleScripting.access(for: source.bundleID, ask: false)
        if result == .notDetermined {
            result = await AppleScripting.access(for: source.bundleID, ask: true)
        }
        access[source] = result
        if result == .granted, !artworkIsFullSize {
            artworkKey = nil // Now allowed: fetch the sharper cover.
            loadArtworkIfNeeded()
        }
        return result == .granted
    }

    public func openAutomationSettings() {
        AppleScripting.openAutomationSettings()
    }

    /// Opens (or brings to the front) a music app. Only call when the user asks.
    public func open(_ source: MediaSourceID) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    public func appIcon(for source: MediaSourceID) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    // MARK: Artwork

    private func loadArtworkIfNeeded() {
        guard let current = nowPlaying else {
            artworkTask?.cancel()
            artwork = nil
            artworkKey = nil
            return
        }
        let key = current.trackKey
        guard key != artworkKey else { return }
        artworkKey = key
        artworkTask?.cancel()
        // Keep the old cover until the new one arrives, so it never flashes empty,
        // unless the app changed, when the old cover would be misleading.
        if previousArtworkSource != current.source { artwork = nil }
        previousArtworkSource = current.source

        let granted = access[current.source] == .granted
        artworkTask = Task { [weak self] in
            let data: Data?
            var fullSize = granted
            switch current.source {
            case .spotify:
                var url = granted ? PlayerScripts.spotifyArtworkURL() : nil
                if url == nil, let id = current.trackID {
                    url = await Artwork.spotifyPublicArtworkURL(for: id)
                    fullSize = false
                }
                data = if let url { await Artwork.download(url) } else { nil }
            case .music:
                data = granted ? PlayerScripts.musicArtworkData() : nil
            }
            guard let self, !Task.isCancelled, self.artworkKey == key else { return }
            self.artwork = data.flatMap { Artwork.image(from: $0) }
            self.artworkIsFullSize = fullSize && self.artwork != nil
        }
    }

    @ObservationIgnored private var previousArtworkSource: MediaSourceID?
}
