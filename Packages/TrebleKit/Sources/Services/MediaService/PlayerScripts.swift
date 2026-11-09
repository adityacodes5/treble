import AppKit

/// The AppleScript for each music app. Spotify and Music share most commands,
/// but differ in units (Spotify: milliseconds) and in how artwork is provided.
@MainActor
enum PlayerScripts {
    /// Reads the current track and state. Used at launch (when the app was
    /// already playing) and to resync position. Only call with access granted.
    static func currentState(of source: MediaSourceID, at now: Date) -> NowPlaying? {
        let body = switch source {
        case .spotify:
            "return {player state as text, name of current track, artist of current track, album of current track, duration of current track, player position, id of current track}"
        case .music:
            "return {player state as text, name of current track, artist of current track, album of current track, duration of current track, player position, persistent ID of current track}"
        }
        guard let result = AppleScripting.run(body, in: source.bundleID) else { return nil }
        let items = result.listItems
        guard items.count == 7 else { return nil }

        let state = items[0].stringValue?.lowercased()
        guard state == "playing" || state == "paused", let title = items[1].stringValue, !title.isEmpty else {
            return nil
        }
        let rawDuration = items[4].doubleValue
        return NowPlaying(
            source: source,
            trackID: source == .spotify ? items[6].stringValue : nil, // See NotificationParsing.
            title: title,
            artist: items[2].stringValue.flatMap { $0.isEmpty ? nil : $0 },
            album: items[3].stringValue.flatMap { $0.isEmpty ? nil : $0 },
            // Spotify: milliseconds. Music: seconds.
            duration: rawDuration > 0 ? (source == .spotify ? rawDuration / 1000 : rawDuration) : nil,
            isPlaying: state == "playing",
            position: items[5].doubleValue,
            positionDate: now
        )
    }

    /// Seconds into the current track.
    static func position(of source: MediaSourceID) -> TimeInterval? {
        AppleScripting.run("return player position", in: source.bundleID)?.doubleValue
    }

    @discardableResult
    static func send(_ command: MediaCommand, to source: MediaSourceID) -> Bool {
        let body = switch command {
        case .playPause: "playpause"
        case .play: "play"
        case .pause: "pause"
        case .next: "next track"
        case .previous: "previous track"
        // AppleScript number literals always use a period, whatever the user's locale.
        case .seek(let seconds): "set player position to \(String(format: "%.2f", max(0, seconds)))"
        }
        return AppleScripting.run(body, in: source.bundleID) != nil
    }

    /// Spotify: the cover image URL (640px). Only call with access granted.
    static func spotifyArtworkURL() -> URL? {
        AppleScripting.run("return artwork url of current track", in: MediaSourceID.spotify.bundleID)?
            .stringValue.flatMap(URL.init(string:))
    }

    /// Music: the cover image itself. Only call with access granted.
    static func musicArtworkData() -> Data? {
        guard let result = AppleScripting.run("return data of artwork 1 of current track", in: MediaSourceID.music.bundleID) else {
            return nil
        }
        let data = result.data
        return data.isEmpty ? nil : data
    }
}
