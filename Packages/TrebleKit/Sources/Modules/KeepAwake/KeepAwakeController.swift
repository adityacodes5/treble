import AppKit
import Observation
import PowerService
import TrebleCore

/// Everything Keep Awake needs from the outside world. Tests swap in fakes.
@MainActor
struct KeepAwakeEnvironment {
    var now: @MainActor () -> Date
    var preventSleep: @MainActor (_ name: String, _ keepDisplayOn: Bool) -> (any TrebleCancellable)?
    var powerSource: @MainActor () -> PowerSourceState
    var isAppRunning: @MainActor (pid_t) -> Bool
    var notify: @MainActor (_ title: String, _ body: String) -> Void
    var schedule: @MainActor (_ date: Date, _ action: @escaping @MainActor () -> Void) -> any TrebleCancellable

    static var live: KeepAwakeEnvironment {
        KeepAwakeEnvironment(
            now: { Date() },
            preventSleep: { PowerService.preventSleep(name: $0, keepDisplayOn: $1) },
            powerSource: { PowerService.powerSource },
            isAppRunning: { pid in
                NSRunningApplication(processIdentifier: pid).map { !$0.isTerminated } ?? false
            },
            notify: { TrebleNotifications.post(title: $0, body: $1) },
            // Ending a few seconds late is harmless; the tolerance lets macOS batch wakeups.
            schedule: { TrebleTimer.once(at: $0, tolerance: 5, $1) }
        )
    }
}

/// Keep Awake's logic: starting and ending sessions, and every rule for when
/// to end one on its own. No UI and no system observers here.
@MainActor
@Observable
final class KeepAwakeController {
    private(set) var session: KeepAwakeSession?
    /// Why the last session ended, when that's worth showing.
    private(set) var endNote: String?
    /// Why the last start was refused.
    private(set) var startError: String?

    let preferences: KeepAwakePreferences
    @ObservationIgnored var onSessionChange: (() -> Void)?

    @ObservationIgnored private let env: KeepAwakeEnvironment
    @ObservationIgnored private var assertion: (any TrebleCancellable)?
    @ObservationIgnored private var endTimer: (any TrebleCancellable)?

    init(preferences: KeepAwakePreferences, environment: KeepAwakeEnvironment) {
        self.preferences = preferences
        self.env = environment
    }

    var isActive: Bool { session != nil }

    // MARK: Starting and stopping

    func start(_ mode: KeepAwakeMode) {
        startError = nil

        if let problem = powerProblem(env.powerSource()) {
            startError = problem.startMessage
            return
        }
        if case .whileRunning(let app) = mode, !env.isAppRunning(app.pid) {
            startError = "\(app.name) isn't running."
            return
        }

        let newSession = KeepAwakeSession(mode: mode, startedAt: env.now())
        if let endDate = newSession.endDate, endDate <= newSession.startedAt {
            startError = "That time has already passed."
            return
        }

        // Take the new assertion before releasing any old one, so there's no gap.
        guard let newAssertion = env.preventSleep(newSession.assertionName, preferences.keepDisplayOn) else {
            startError = "macOS didn't allow Treble to keep your Mac awake."
            return
        }
        releaseResources()
        assertion = newAssertion
        session = newSession
        endNote = nil
        scheduleEnd()
        onSessionChange?()
    }

    /// Starts the default duration, or stops if already on. What clicking the cup does.
    func toggle() {
        if isActive {
            stop(.user)
        } else {
            start(preferences.defaultMode)
        }
    }

    func stop(_ reason: KeepAwakeEndReason) {
        guard session != nil else { return }
        releaseResources()
        session = nil
        endNote = reason.note
        if let notification = reason.notification {
            env.notify(notification.title, notification.body)
        }
        onSessionChange?()
    }

    // MARK: Things that can end a session

    /// After waking from sleep or a clock change: end the session if its time
    /// has passed, otherwise re-aim the timer at the (wall-clock) end time.
    func refreshTiming() {
        guard let session else { return }
        if let endDate = session.endDate, endDate <= env.now() {
            stop(.expired)
        } else {
            scheduleEnd()
        }
    }

    func powerSourceChanged(_ state: PowerSourceState) {
        guard isActive, let problem = powerProblem(state) else { return }
        stop(problem.endReason)
    }

    func appTerminated(pid: pid_t) {
        guard case .whileRunning(let app)? = session?.mode, app.pid == pid else { return }
        stop(.appQuit(app.name))
    }

    /// The user changed a setting.
    func preferencesChanged(_ change: KeepAwakePreferences.Change) {
        guard let session else { return }
        switch change {
        case .display:
            // Swap the assertion type, taking the new one first so there's no gap.
            if let replacement = env.preventSleep(session.assertionName, preferences.keepDisplayOn) {
                assertion?.cancel()
                assertion = replacement
            }
        case .power:
            powerSourceChanged(env.powerSource())
        case .menuBar:
            break
        }
    }

    // MARK: Helpers

    private enum PowerProblem {
        case lowBattery(Int)
        case unplugged

        var endReason: KeepAwakeEndReason {
            switch self {
            case .lowBattery(let threshold): .lowBattery(threshold: threshold)
            case .unplugged: .unplugged
            }
        }

        var startMessage: String {
            switch self {
            case .lowBattery(let threshold): "Battery is below \(threshold)%. Plug in, or change this in Settings."
            case .unplugged: "Set to work only while plugged in. Plug in, or change this in Settings."
            }
        }
    }

    private func powerProblem(_ state: PowerSourceState) -> PowerProblem? {
        guard state.isOnBattery else { return nil }
        if preferences.onlyWhilePluggedIn {
            return .unplugged
        }
        if preferences.stopOnLowBattery, let percent = state.batteryPercent,
           percent < preferences.lowBatteryThreshold {
            return .lowBattery(preferences.lowBatteryThreshold)
        }
        return nil
    }

    private func scheduleEnd() {
        endTimer?.cancel()
        endTimer = nil
        guard let endDate = session?.endDate else { return }
        endTimer = env.schedule(endDate) { [weak self] in
            self?.refreshTiming()
        }
    }

    private func releaseResources() {
        endTimer?.cancel()
        endTimer = nil
        assertion?.cancel()
        assertion = nil
    }
}
