import Foundation

/// A music app Treble can show and control.
public enum MediaSourceID: String, CaseIterable, Sendable {
    case spotify
    case music

    public var bundleID: String {
        switch self {
        case .spotify: "com.spotify.client"
        case .music: "com.apple.Music"
        }
    }

    public var displayName: String {
        switch self {
        case .spotify: "Spotify"
        case .music: "Music"
        }
    }
}

/// What's playing right now.
public struct NowPlaying: Equatable, Sendable {
    public var source: MediaSourceID
    /// The app's own ID for the track, when it gives one ("spotify:track:…").
    public var trackID: String?
    public var title: String
    public var artist: String?
    public var album: String?
    /// Track length in seconds, or nil for live streams.
    public var duration: TimeInterval?
    public var isPlaying: Bool
    /// Seconds into the track at `positionDate`, or nil if unknown.
    public var position: TimeInterval?
    public var positionDate: Date

    public init(
        source: MediaSourceID,
        trackID: String? = nil,
        title: String,
        artist: String? = nil,
        album: String? = nil,
        duration: TimeInterval? = nil,
        isPlaying: Bool,
        position: TimeInterval? = nil,
        positionDate: Date
    ) {
        self.source = source
        self.trackID = trackID
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.isPlaying = isPlaying
        self.position = position
        self.positionDate = positionDate
    }

    /// Identifies the track (not the moment), for artwork and "did the song change?".
    public var trackKey: String {
        trackID ?? [source.rawValue, title, artist ?? "", album ?? ""].joined(separator: "|")
    }

    /// Seconds into the track at `now`, worked out from the last report
    /// instead of asking the app every second.
    public func elapsed(at now: Date) -> TimeInterval? {
        guard let position else { return nil }
        var elapsed = position
        if isPlaying {
            elapsed += max(0, now.timeIntervalSince(positionDate))
        }
        if let duration {
            elapsed = min(elapsed, duration)
        }
        return max(0, elapsed)
    }

    /// True when the difference is only the clock moving on as expected,
    /// so nothing on screen needs to change.
    public func looksTheSame(as other: NowPlaying, at now: Date) -> Bool {
        guard source == other.source, trackKey == other.trackKey, title == other.title,
              artist == other.artist, album == other.album, duration == other.duration,
              isPlaying == other.isPlaying else { return false }
        switch (elapsed(at: now), other.elapsed(at: now)) {
        case (nil, nil): return true
        case let (a?, b?): return abs(a - b) < 1.5
        default: return false
        }
    }
}

/// Something the user can ask the music app to do.
public enum MediaCommand: Equatable, Sendable {
    case playPause
    case play
    case pause
    case next
    case previous
    case seek(to: TimeInterval)
}

/// Whether macOS lets Treble control a music app (Privacy & Security → Automation).
public enum ControlAccess: Equatable, Sendable {
    case granted
    case denied
    case notDetermined
    case appNotRunning
    case unknown
}
