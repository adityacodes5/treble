import Foundation

/// Spotify and Music broadcast a system-wide notification every time a track
/// changes, plays or pauses. Reading it needs no permission and no polling.
enum PlayerNotifications {
    static let spotify = Notification.Name("com.spotify.client.PlaybackStateChanged")
    static let music = Notification.Name("com.apple.Music.playerInfo")

    static func name(for source: MediaSourceID) -> Notification.Name {
        switch source {
        case .spotify: spotify
        case .music: music
        }
    }

    /// Turns a notification's info into `NowPlaying`, or nil when playback stopped.
    static func parse(_ info: [AnyHashable: Any], from source: MediaSourceID, at now: Date) -> NowPlaying? {
        let state = (info["Player State"] as? String)?.lowercased()
        guard state == "playing" || state == "paused" else { return nil }

        let title = nonEmpty(info["Name"]) ?? nonEmpty(info["Stream Title"])
        guard let title else { return nil }

        switch source {
        case .spotify:
            return NowPlaying(
                source: .spotify,
                trackID: nonEmpty(info["Track ID"]),
                title: title,
                artist: nonEmpty(info["Artist"]),
                album: nonEmpty(info["Album"]),
                // Spotify reports duration in milliseconds and position in seconds.
                duration: number(info["Duration"]).flatMap { $0 > 0 ? $0 / 1000 : nil },
                isPlaying: state == "playing",
                position: number(info["Playback Position"]),
                positionDate: now
            )
        case .music:
            return NowPlaying(
                source: .music,
                // Music's broadcast and its AppleScript give the ID in different
                // forms (number vs hex), so tracks are matched by name instead.
                trackID: nil,
                title: title,
                artist: nonEmpty(info["Artist"]),
                album: nonEmpty(info["Album"]),
                // Music reports milliseconds and no position; MediaService fills that in.
                duration: number(info["Total Time"]).flatMap { $0 > 0 ? $0 / 1000 : nil },
                isPlaying: state == "playing",
                position: nil,
                positionDate: now
            )
        }
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
}

/// Pure decision-making, kept separate so it can be tested.
enum NowPlayingLogic {
    /// Fills in what a new report leaves out, using the previous one.
    ///
    /// Music never reports position, so: a new track that's playing starts at
    /// 0; the same track keeps counting from where it was (frozen while paused).
    static func merge(previous: NowPlaying?, incoming: NowPlaying, at now: Date) -> NowPlaying {
        guard incoming.position == nil else { return incoming }
        var merged = incoming
        if let previous, previous.trackKey == incoming.trackKey {
            merged.position = previous.elapsed(at: now)
        } else if incoming.isPlaying {
            merged.position = 0
        }
        merged.positionDate = now
        return merged
    }

    /// Which app to show when several have something loaded: the one that
    /// most recently started playing; otherwise the one most recently paused.
    static func pick(states: [MediaSourceID: NowPlaying], startedPlaying: [MediaSourceID: Date]) -> NowPlaying? {
        let playing = states.values.filter(\.isPlaying)
        if !playing.isEmpty {
            return playing.max { (startedPlaying[$0.source] ?? .distantPast) < (startedPlaying[$1.source] ?? .distantPast) }
        }
        return states.values.max { $0.positionDate < $1.positionDate }
    }

    /// Spotify's public page URL for a track or episode ID, used to look up artwork.
    static func spotifyPageURL(for trackID: String) -> URL? {
        let parts = trackID.split(separator: ":")
        guard parts.count == 3, parts[0] == "spotify", ["track", "episode"].contains(parts[1]) else { return nil }
        return URL(string: "https://open.spotify.com/\(parts[1])/\(parts[2])")
    }
}
