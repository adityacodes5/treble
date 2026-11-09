import MediaService
import SwiftUI
import TrebleCore

// MARK: - Popover (click the song in the menu bar)

struct NowPlayingPopover: View {
    let media: MediaService
    let accessory: AnyView

    var body: some View {
        Group {
            if let nowPlaying = media.nowPlaying {
                VStack(alignment: .leading, spacing: 12) {
                    AlbumArt(image: media.artwork, trackKey: nowPlaying.trackKey, size: 280, cornerRadius: 10)
                    TrackInfo(nowPlaying: nowPlaying, titleFont: .headline)
                    Scrubber(media: media, nowPlaying: nowPlaying)
                    Controls(media: media, nowPlaying: nowPlaying, size: .large)
                    AccessHint(media: media, source: nowPlaying.source)
                    accessory
                    SourceButton(media: media, source: nowPlaying.source)
                }
            } else {
                NothingPlaying(media: media)
            }
        }
        .onAppear {
            // Correct any drift in the progress bar, once, when it's shown.
            media.refreshPosition()
            Task { await media.refreshAccess() }
        }
    }
}

// MARK: - Tile (in the panel)

struct NowPlayingTile: View {
    let media: MediaService

    var body: some View {
        if let nowPlaying = media.nowPlaying {
            HStack(spacing: 10) {
                Button { media.open(nowPlaying.source) } label: {
                    AlbumArt(image: media.artwork, trackKey: nowPlaying.trackKey, size: 44, cornerRadius: 6)
                }
                .buttonStyle(.plain)
                .help("Open \(nowPlaying.source.displayName)")

                TrackInfo(nowPlaying: nowPlaying, titleFont: .subheadline.weight(.semibold))
                Spacer(minLength: 4)
                Controls(media: media, nowPlaying: nowPlaying, size: .small)
            }
        } else {
            HStack(spacing: 10) {
                TileToggleIcon("music.note", isOn: false)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Now Playing").font(.headline)
                    Text("Nothing playing").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                OpenAppMenu(media: media)
            }
        }
    }
}

// MARK: - Pieces

struct AlbumArt: View {
    let image: NSImage?
    let trackKey: String
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.quaternary)
            Image(systemName: "music.note")
                .font(.system(size: size * 0.3, weight: .light))
                .foregroundStyle(.tertiary)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .id(ObjectIdentifier(image))
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .animation(.easeInOut(duration: 0.25), value: image.map(ObjectIdentifier.init))
        .accessibilityHidden(true)
    }
}

struct TrackInfo: View {
    let nowPlaying: NowPlaying
    let titleFont: Font

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(nowPlaying.title)
                .font(titleFont)
                .lineLimit(1)
            if let artist = nowPlaying.artist {
                Text(artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let album = nowPlaying.album, titleFont == .headline {
                Text(album)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .help([nowPlaying.title, nowPlaying.artist, nowPlaying.album].compactMap { $0 }.joined(separator: " — "))
    }
}

/// The progress bar. Ticks once a second, only while the popover is open.
struct Scrubber: View {
    let media: MediaService
    let nowPlaying: NowPlaying
    @State private var dragPosition: Double?

    var body: some View {
        if let duration = nowPlaying.duration {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let elapsed = dragPosition ?? nowPlaying.elapsed(at: timeline.date) ?? 0
                VStack(spacing: 2) {
                    Slider(
                        value: Binding(
                            get: { min(elapsed, duration) },
                            set: { dragPosition = $0 }
                        ),
                        in: 0...max(duration, 1)
                    ) { editing in
                        if !editing, let target = dragPosition {
                            Task {
                                await media.send(.seek(to: target))
                                dragPosition = nil
                            }
                        }
                    }
                    .controlSize(.mini)
                    .disabled(nowPlaying.position == nil)
                    .accessibilityLabel("Position")

                    HStack {
                        Text(Ticker.time(elapsed))
                        Spacer()
                        Text("-" + Ticker.time(duration - elapsed))
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct Controls: View {
    enum Size { case small, large }

    let media: MediaService
    let nowPlaying: NowPlaying
    let size: Size

    var body: some View {
        HStack(spacing: size == .large ? 28 : 12) {
            button("backward.fill", "Previous", .previous)
            button(nowPlaying.isPlaying ? "pause.fill" : "play.fill", nowPlaying.isPlaying ? "Pause" : "Play", .playPause)
                .font(.system(size: size == .large ? 26 : 16))
            button("forward.fill", "Next", .next)
        }
        .font(.system(size: size == .large ? 18 : 12))
        .frame(maxWidth: size == .large ? .infinity : nil)
    }

    private func button(_ symbol: String, _ label: String, _ command: MediaCommand) -> some View {
        Button {
            Task { await media.send(command) }
        } label: {
            Image(systemName: symbol)
                .frame(minWidth: 24, minHeight: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .disabled(media.access[nowPlaying.source] == .denied)
    }
}

/// Shown only when controls won't work, with a way to fix it.
struct AccessHint: View {
    let media: MediaService
    let source: MediaSourceID

    var body: some View {
        if media.access[source] == .denied {
            VStack(alignment: .leading, spacing: 6) {
                Text("To use the controls, allow Treble to control \(source.displayName) in Privacy & Security → Automation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open System Settings") { media.openAutomationSettings() }
                    .controlSize(.small)
            }
        }
    }
}

struct SourceButton: View {
    let media: MediaService
    let source: MediaSourceID

    var body: some View {
        Button { media.open(source) } label: {
            HStack(spacing: 6) {
                if let icon = media.appIcon(for: source) {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                }
                Text("Open \(source.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

struct NothingPlaying: View {
    let media: MediaService

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Nothing playing")
                .font(.headline)
            Text(media.installedSources.isEmpty
                 ? "Now Playing works with Spotify and Apple Music."
                 : "Play something in \(media.installedSources.map(\.displayName).formatted(.list(type: .or))).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                ForEach(media.installedSources, id: \.self) { source in
                    Button("Open \(source.displayName)") { media.open(source) }
                        .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

struct OpenAppMenu: View {
    let media: MediaService

    var body: some View {
        let sources = media.installedSources
        if !sources.isEmpty {
            Menu {
                ForEach(sources, id: \.self) { source in
                    Button("Open \(source.displayName)") { media.open(source) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Open a music app")
        }
    }
}

// MARK: - Settings

struct NowPlayingSettings: View {
    @Bindable var preferences: NowPlayingPreferences
    let media: MediaService

    var body: some View {
        Form {
            Section {
                Picker("Show", selection: $preferences.tickerStyle) {
                    ForEach(TickerStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                if preferences.tickerStyle != .iconOnly {
                    Picker("Maximum width", selection: $preferences.maxWidth) {
                        ForEach(NowPlayingPreferences.widthChoices, id: \.self) { width in
                            Text(widthName(width)).tag(width)
                        }
                    }
                }
                Toggle("Dim while paused", isOn: $preferences.dimWhenPaused)
                Toggle("Hide when nothing is playing", isOn: $preferences.hideWhenIdle)
            } header: {
                Text("Menu bar")
            } footer: {
                Text("Middle-click the song to play or pause. After 5 minutes paused, only the icon shows.")
            }

            Section {
                ForEach(MediaSourceID.allCases, id: \.self) { source in
                    AccessRow(media: media, source: source)
                }
            } header: {
                Text("Controls")
            } footer: {
                Text("Showing the song needs no permission. Play, pause and skip need permission to control each app, which macOS asks for the first time you use them.")
            }

            Section {
                Label {
                    Text("Album art for Spotify songs is loaded from Spotify's servers, the same place the Spotify app gets it. Nothing about your listening is saved or sent anywhere else.")
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "hand.raised")
                }
                .font(.callout)
            }
        }
        .formStyle(.grouped)
        .task { await media.refreshAccess() }
    }

    private func widthName(_ width: Double) -> String {
        switch width {
        case ...120: "Narrow"
        case ...160: "Medium"
        case ...220: "Wide"
        default: "Extra wide"
        }
    }
}

private struct AccessRow: View {
    let media: MediaService
    let source: MediaSourceID

    var body: some View {
        let installed = media.installedSources.contains(source)
        LabeledContent {
            if !installed {
                Text("Not installed").foregroundStyle(.secondary)
            } else {
                switch media.access[source] ?? .unknown {
                case .granted:
                    Label("Allowed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .denied:
                    Button("Open System Settings") { media.openAutomationSettings() }
                case .notDetermined:
                    Button("Allow…") { Task { await media.ensureAccess(for: source) } }
                case .appNotRunning, .unknown:
                    Text("Open \(source.displayName) to check").foregroundStyle(.secondary)
                }
            }
        } label: {
            HStack(spacing: 8) {
                if let icon = media.appIcon(for: source) {
                    Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                }
                Text(source.displayName)
            }
        }
    }
}
