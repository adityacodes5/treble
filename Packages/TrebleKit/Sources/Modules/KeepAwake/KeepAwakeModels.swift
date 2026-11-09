import AppKit
import Observation
import TrebleCore

/// An app Keep Awake can wait for ("keep awake while Xcode is running").
struct WatchedApp: Equatable, Sendable {
    let name: String
    let pid: pid_t

    /// Regular apps that are running now, sorted by name. Excludes Treble itself.
    @MainActor
    static func running() -> [WatchedApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0 != .current && !$0.isTerminated }
            .map { WatchedApp(name: $0.localizedName ?? "App \($0.processIdentifier)", pid: $0.processIdentifier) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// How long to keep the Mac awake.
enum KeepAwakeMode: Equatable, Sendable {
    case duration(TimeInterval)
    case until(Date)
    case whileRunning(WatchedApp)
    case indefinitely

    /// The quick choices shown as buttons in the tile.
    static let quickDurations: [TimeInterval] = [15 * 60, 30 * 60, 3600, 2 * 3600, 5 * 3600]

    func endDate(startingAt start: Date) -> Date? {
        switch self {
        case .duration(let seconds): start.addingTimeInterval(seconds)
        case .until(let date): date
        case .whileRunning, .indefinitely: nil
        }
    }
}

/// A running Keep Awake session.
struct KeepAwakeSession: Equatable, Sendable {
    let mode: KeepAwakeMode
    let startedAt: Date
    /// When it ends on its own, or nil if it waits for an app or runs indefinitely.
    let endDate: Date?

    init(mode: KeepAwakeMode, startedAt: Date) {
        self.mode = mode
        self.startedAt = startedAt
        self.endDate = mode.endDate(startingAt: startedAt)
    }

    /// Shown in `pmset -g assertions`, so it's clear why the Mac is awake.
    var assertionName: String {
        switch mode {
        case .duration, .until:
            "Treble Keep Awake (until \(endDate.map(Format.time) ?? "later"))"
        case .whileRunning(let app):
            "Treble Keep Awake (while \(app.name) is running)"
        case .indefinitely:
            "Treble Keep Awake (indefinitely)"
        }
    }
}

/// Why a session ended. Shown briefly in the tile.
enum KeepAwakeEndReason: Equatable, Sendable {
    case user
    case expired
    case lowBattery(threshold: Int)
    case unplugged
    case appQuit(String)

    /// A line for the tile, or nil when there's nothing worth saying.
    var note: String? {
        switch self {
        case .user, .expired: nil
        case .lowBattery(let threshold): "Stopped: battery fell below \(threshold)%"
        case .unplugged: "Stopped: Mac was unplugged"
        case .appQuit(let name): "Stopped: \(name) quit"
        }
    }

    /// A notification to post, or nil when the user caused it or expected it.
    var notification: (title: String, body: String)? {
        switch self {
        case .user, .expired:
            nil
        case .lowBattery(let threshold):
            ("Keep Awake stopped", "Your battery fell below \(threshold)%, so your Mac can sleep again.")
        case .unplugged:
            ("Keep Awake stopped", "Your Mac was unplugged, so it can sleep again.")
        case .appQuit(let name):
            ("Keep Awake stopped", "\(name) quit, so your Mac can sleep again.")
        }
    }
}

/// Keep Awake's settings, saved under "keepAwake.*".
@MainActor
@Observable
final class KeepAwakePreferences {
    enum Change { case display, power, menuBar }

    /// Also keep the screen on (off by default, which saves battery).
    var keepDisplayOn: Bool { didSet { save(keepDisplayOn, "keepDisplayOn", .display) } }
    /// Stop automatically when the battery runs low (on by default).
    var stopOnLowBattery: Bool { didSet { save(stopOnLowBattery, "stopOnLowBattery", .power) } }
    var lowBatteryThreshold: Int { didSet { save(lowBatteryThreshold, "lowBatteryThreshold", .power) } }
    /// Only keep awake while plugged in (off by default).
    var onlyWhilePluggedIn: Bool { didSet { save(onlyWhilePluggedIn, "onlyWhilePluggedIn", .power) } }
    /// Show the time left next to the menu bar icon (off by default).
    var showTimeInMenuBar: Bool { didSet { save(showTimeInMenuBar, "showTimeInMenuBar", .menuBar) } }
    /// What clicking the cup starts. Zero means indefinitely.
    var defaultDuration: TimeInterval { didSet { save(defaultDuration, "defaultDuration", nil) } }

    static let thresholdChoices = [10, 20, 30, 50]

    @ObservationIgnored var onChange: ((Change) -> Void)?
    @ObservationIgnored private let settings: ModuleSettings?

    /// Pass nil (in tests) to use the defaults without saving anything.
    init(settings: ModuleSettings?) {
        self.settings = settings
        keepDisplayOn = settings?.value("keepDisplayOn", default: false) ?? false
        stopOnLowBattery = settings?.value("stopOnLowBattery", default: true) ?? true
        lowBatteryThreshold = settings?.value("lowBatteryThreshold", default: 20) ?? 20
        onlyWhilePluggedIn = settings?.value("onlyWhilePluggedIn", default: false) ?? false
        showTimeInMenuBar = settings?.value("showTimeInMenuBar", default: false) ?? false
        defaultDuration = settings?.value("defaultDuration", default: 3600.0) ?? 3600
    }

    var defaultMode: KeepAwakeMode {
        defaultDuration > 0 ? .duration(defaultDuration) : .indefinitely
    }

    private func save(_ value: Any, _ key: String, _ change: Change?) {
        settings?.set(value, for: key)
        if let change { onChange?(change) }
    }
}

/// Shared text formatting.
enum Format {
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "1h 12m", "12m", or "<1m".
    static func remaining(_ seconds: TimeInterval) -> String {
        guard seconds >= 60 else { return "<1m" }
        let minutes = Int((seconds / 60).rounded(.up))
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    /// "15m", "1h", "∞" for the quick buttons.
    static func choice(_ seconds: TimeInterval) -> String {
        seconds <= 0 ? "∞" : remaining(seconds)
    }
}

extension Calendar {
    /// The next time the clock shows `hour:minute`: today if it's still ahead, otherwise tomorrow.
    func nextOccurrence(hour: Int, minute: Int, after now: Date) -> Date {
        let today = date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
        if today > now { return today }
        return date(byAdding: .day, value: 1, to: today) ?? today
    }
}
