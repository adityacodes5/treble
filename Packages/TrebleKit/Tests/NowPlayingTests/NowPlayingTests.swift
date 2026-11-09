import Foundation
import Testing
import TrebleCore
@testable import MediaService
@testable import NowPlaying

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func spotifyInfo(
    state: String = "Playing",
    name: String = "Song",
    id: String = "spotify:track:abc123",
    position: Double = 12.5,
    duration: Int = 200_000
) -> [AnyHashable: Any] {
    [
        "Player State": state,
        "Name": name,
        "Artist": "Artist",
        "Album": "Album",
        "Track ID": id,
        "Playback Position": NSNumber(value: position),
        "Duration": NSNumber(value: duration),
    ]
}

private func track(
    _ source: MediaSourceID = .spotify,
    title: String = "Song",
    playing: Bool = true,
    position: Double? = 0,
    at date: Date = t0
) -> NowPlaying {
    NowPlaying(source: source, title: title, artist: "Artist", duration: 200,
               isPlaying: playing, position: position, positionDate: date)
}

// MARK: - Parsing the apps' broadcasts

@Suite struct ParsingTests {
    @Test func spotifyPlaying() throws {
        let parsed = try #require(PlayerNotifications.parse(spotifyInfo(), from: .spotify, at: t0))
        #expect(parsed.title == "Song")
        #expect(parsed.artist == "Artist")
        #expect(parsed.album == "Album")
        #expect(parsed.trackID == "spotify:track:abc123")
        #expect(parsed.duration == 200) // milliseconds → seconds
        #expect(parsed.position == 12.5) // already seconds
        #expect(parsed.isPlaying)
    }

    @Test func spotifyPausedAndStopped() {
        #expect(PlayerNotifications.parse(spotifyInfo(state: "Paused"), from: .spotify, at: t0)?.isPlaying == false)
        #expect(PlayerNotifications.parse(spotifyInfo(state: "Stopped"), from: .spotify, at: t0) == nil)
        #expect(PlayerNotifications.parse([:], from: .spotify, at: t0) == nil)
    }

    @Test func blankTitleIsIgnored() {
        #expect(PlayerNotifications.parse(spotifyInfo(name: "  "), from: .spotify, at: t0) == nil)
    }

    @Test func musicHasNoPositionAndMatchesByName() throws {
        let info: [AnyHashable: Any] = [
            "Player State": "Playing", "Name": "Song", "Artist": "Artist",
            "Total Time": NSNumber(value: 180_000), "PersistentID": NSNumber(value: -123_456_789),
        ]
        let parsed = try #require(PlayerNotifications.parse(info, from: .music, at: t0))
        #expect(parsed.duration == 180)
        #expect(parsed.position == nil)
        #expect(parsed.trackID == nil)
        #expect(parsed.album == nil)
    }

    @Test func liveStreamHasNoDuration() throws {
        let parsed = try #require(PlayerNotifications.parse(spotifyInfo(duration: 0), from: .spotify, at: t0))
        #expect(parsed.duration == nil)
    }

    @Test func spotifyPageURLs() {
        #expect(NowPlayingLogic.spotifyPageURL(for: "spotify:track:abc")?.absoluteString == "https://open.spotify.com/track/abc")
        #expect(NowPlayingLogic.spotifyPageURL(for: "spotify:episode:xyz")?.absoluteString == "https://open.spotify.com/episode/xyz")
        #expect(NowPlayingLogic.spotifyPageURL(for: "spotify:ad:123") == nil)
        #expect(NowPlayingLogic.spotifyPageURL(for: "spotify:local:a:b:c:1") == nil)
    }
}

// MARK: - Position, merging and choosing a source

@Suite struct LogicTests {
    @Test func elapsedCountsOnlyWhilePlaying() {
        #expect(track(position: 10).elapsed(at: t0 + 5) == 15)
        #expect(track(playing: false, position: 10).elapsed(at: t0 + 5) == 10)
        #expect(track(position: 195).elapsed(at: t0 + 60) == 200) // never past the end
        #expect(track(position: nil).elapsed(at: t0) == nil)
    }

    @Test func musicSameTrackKeepsCounting() {
        let previous = track(.music, position: 30)
        let pausedReport = track(.music, playing: false, position: nil, at: t0 + 10)
        let merged = NowPlayingLogic.merge(previous: previous, incoming: pausedReport, at: t0 + 10)
        #expect(merged.position == 40)
        #expect(merged.elapsed(at: t0 + 100) == 40) // frozen while paused
    }

    @Test func musicNewTrackStartsAtZero() {
        let previous = track(.music, title: "Old", position: 90)
        let merged = NowPlayingLogic.merge(previous: previous, incoming: track(.music, title: "New", position: nil), at: t0)
        #expect(merged.position == 0)
    }

    @Test func musicNewTrackPausedHasUnknownPosition() {
        let merged = NowPlayingLogic.merge(previous: nil, incoming: track(.music, playing: false, position: nil), at: t0)
        #expect(merged.position == nil)
    }

    @Test func reportedPositionWins() {
        let incoming = track(position: 5)
        #expect(NowPlayingLogic.merge(previous: track(position: 100), incoming: incoming, at: t0) == incoming)
    }

    @Test func picksMostRecentlyStartedPlayer() {
        let states: [MediaSourceID: NowPlaying] = [.spotify: track(.spotify), .music: track(.music)]
        let picked = NowPlayingLogic.pick(states: states, startedPlaying: [.spotify: t0, .music: t0 + 1])
        #expect(picked?.source == .music)
    }

    @Test func playingBeatsPaused() {
        let states: [MediaSourceID: NowPlaying] = [
            .spotify: track(.spotify, playing: true, at: t0),
            .music: track(.music, playing: false, at: t0 + 100),
        ]
        #expect(NowPlayingLogic.pick(states: states, startedPlaying: [.spotify: t0])?.source == .spotify)
    }

    @Test func otherwiseMostRecentlyPaused() {
        let states: [MediaSourceID: NowPlaying] = [
            .spotify: track(.spotify, playing: false, at: t0),
            .music: track(.music, playing: false, at: t0 + 100),
        ]
        #expect(NowPlayingLogic.pick(states: states, startedPlaying: [:])?.source == .music)
        #expect(NowPlayingLogic.pick(states: [:], startedPlaying: [:]) == nil)
    }

    @Test func clockMovingOnIsNotAChange() {
        let a = track(position: 10, at: t0)
        let b = track(position: 15, at: t0 + 5)
        #expect(a.looksTheSame(as: b, at: t0 + 5))
        #expect(!a.looksTheSame(as: track(position: 60, at: t0 + 5), at: t0 + 5)) // a seek
        #expect(!a.looksTheSame(as: track(playing: false, position: 15, at: t0 + 5), at: t0 + 5))
    }
}

// MARK: - Menu bar ticker

@Suite struct TickerTests {
    private func label(
        _ nowPlaying: NowPlaying?,
        style: TickerStyle = .titleArtist,
        hideWhenIdle: Bool = false,
        pausedFor: TimeInterval = 0
    ) -> MenuBarLabel {
        Ticker.label(for: nowPlaying, style: style, maxWidth: 160, dimWhenPaused: true,
                     hideWhenIdle: hideWhenIdle, pausedFor: pausedFor)
    }

    @Test func playingShowsText() {
        let result = label(track())
        #expect(result.text == "Song — Artist")
        #expect(result.symbol == nil)
        #expect(result.maxWidth == 160)
        #expect(!result.isDimmed)
        #expect(result.toolTip == "Song — Artist")
    }

    @Test func styles() {
        #expect(label(track(), style: .title).text == "Song")
        #expect(label(track(), style: .artistTitle).text == "Artist — Song")
        #expect(label(track(), style: .iconOnly).text == nil)
        #expect(label(track(), style: .iconOnly).symbol == Ticker.symbol)
    }

    @Test func missingArtistShowsTitleOnly() {
        var noArtist = track()
        noArtist.artist = nil
        #expect(label(noArtist, style: .artistTitle).text == "Song")
    }

    @Test func pausedDimsThenCollapses() {
        let paused = track(playing: false)
        #expect(label(paused, pausedFor: 10).isDimmed)
        #expect(label(paused, pausedFor: 10).text == "Song — Artist")
        let collapsed = label(paused, pausedFor: Ticker.pausedCollapseDelay)
        #expect(collapsed.text == nil)
        #expect(collapsed.symbol == Ticker.symbol)
    }

    @Test func idleShowsIconOrHides() {
        #expect(label(nil).symbol == Ticker.symbol)
        #expect(!label(nil).isHidden)
        #expect(label(nil, hideWhenIdle: true).isHidden)
    }

    @Test func timeFormatting() {
        #expect(Ticker.time(0) == "0:00")
        #expect(Ticker.time(187.9) == "3:07")
        #expect(Ticker.time(3765) == "1:02:45")
        #expect(Ticker.time(-3) == "0:00")
    }
}
