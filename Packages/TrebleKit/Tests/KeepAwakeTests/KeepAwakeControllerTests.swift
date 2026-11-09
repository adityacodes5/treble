import Foundation
import PowerService
import Testing
import TrebleCore
@testable import KeepAwake

// MARK: - Fakes

@MainActor
final class FakeAssertion: TrebleCancellable {
    let name: String
    let keepsDisplayOn: Bool
    private(set) var isCancelled = false

    init(name: String, keepsDisplayOn: Bool) {
        self.name = name
        self.keepsDisplayOn = keepsDisplayOn
    }

    func cancel() { isCancelled = true }
}

@MainActor
final class FakeTimer: TrebleCancellable {
    let date: Date
    let action: @MainActor () -> Void
    private(set) var isCancelled = false

    init(date: Date, action: @escaping @MainActor () -> Void) {
        self.date = date
        self.action = action
    }

    func cancel() { isCancelled = true }
}

/// A stand-in for the outside world: clock, power, running apps, notifications.
@MainActor
final class FakeWorld {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    var power = PowerSourceState(isOnBattery: false, batteryPercent: 80)
    var runningPIDs: Set<pid_t> = []
    var refusesAssertions = false
    private(set) var assertions: [FakeAssertion] = []
    private(set) var timers: [FakeTimer] = []
    private(set) var notifications: [String] = []

    var liveAssertions: [FakeAssertion] { assertions.filter { !$0.isCancelled } }
    var liveTimers: [FakeTimer] { timers.filter { !$0.isCancelled } }

    var environment: KeepAwakeEnvironment {
        KeepAwakeEnvironment(
            now: { self.now },
            preventSleep: { name, display in
                guard !self.refusesAssertions else { return nil }
                let assertion = FakeAssertion(name: name, keepsDisplayOn: display)
                self.assertions.append(assertion)
                return assertion
            },
            powerSource: { self.power },
            isAppRunning: { self.runningPIDs.contains($0) },
            notify: { title, body in self.notifications.append("\(title): \(body)") },
            schedule: { date, action in
                let timer = FakeTimer(date: date, action: action)
                self.timers.append(timer)
                return timer
            }
        )
    }

    /// Moves the clock forward and fires any timers that are due.
    func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
        for timer in liveTimers where timer.date <= now {
            timer.action()
        }
    }
}

// MARK: - Tests

@MainActor
struct KeepAwakeControllerTests {
    let world = FakeWorld()
    let preferences = KeepAwakePreferences(settings: nil)
    let controller: KeepAwakeController

    init() {
        controller = KeepAwakeController(preferences: preferences, environment: world.environment)
    }

    @Test func startsOffAndTakesNothing() {
        #expect(!controller.isActive)
        #expect(world.assertions.isEmpty)
    }

    @Test func durationKeepsAwakeThenEndsOnTime() {
        controller.start(.duration(3600))
        #expect(controller.isActive)
        #expect(world.liveAssertions.count == 1)
        #expect(world.liveAssertions[0].name.hasPrefix("Treble Keep Awake (until "))
        #expect(!world.liveAssertions[0].keepsDisplayOn, "Display may sleep by default")
        #expect(world.liveTimers.first?.date == world.now.addingTimeInterval(3600))

        world.advance(by: 3599)
        #expect(controller.isActive)

        world.advance(by: 1)
        #expect(!controller.isActive)
        #expect(world.liveAssertions.isEmpty)
        #expect(world.liveTimers.isEmpty)
        #expect(controller.endNote == nil, "Ending on time needs no message")
        #expect(world.notifications.isEmpty)
    }

    @Test func stoppingReleasesEverything() {
        controller.start(.duration(900))
        controller.stop(.user)
        #expect(!controller.isActive)
        #expect(world.liveAssertions.isEmpty)
        #expect(world.liveTimers.isEmpty)
    }

    @Test func startingAgainReplacesTheSessionWithoutAGap() {
        controller.start(.duration(900))
        let first = world.assertions[0]
        controller.start(.duration(7200))

        #expect(first.isCancelled)
        #expect(world.liveAssertions.count == 1)
        #expect(world.liveTimers.count == 1)
        #expect(controller.session?.mode == .duration(7200))
    }

    @Test func toggleUsesTheDefaultDuration() {
        preferences.defaultDuration = 1800
        controller.toggle()
        #expect(controller.session?.mode == .duration(1800))
        controller.toggle()
        #expect(!controller.isActive)

        preferences.defaultDuration = 0
        controller.toggle()
        #expect(controller.session?.mode == .indefinitely)
        #expect(world.liveTimers.isEmpty, "Indefinite sessions have no end timer")
    }

    // MARK: Sleep, wake and clock changes

    @Test func wakingAfterTheEndTimeEndsTheSession() {
        controller.start(.duration(3600))
        // The Mac slept through the end time; no timer fired.
        world.now = world.now.addingTimeInterval(5 * 3600)
        controller.refreshTiming()
        #expect(!controller.isActive)
        #expect(world.liveAssertions.isEmpty)
    }

    @Test func wakingBeforeTheEndTimeKeepsGoing() {
        controller.start(.duration(3600))
        world.now = world.now.addingTimeInterval(600)
        controller.refreshTiming()
        #expect(controller.isActive)
        #expect(world.liveTimers.count == 1, "Timer re-aimed, not duplicated")
    }

    @Test func untilATimeThatAlreadyPassedIsRefused() {
        controller.start(.until(world.now.addingTimeInterval(-60)))
        #expect(!controller.isActive)
        #expect(controller.startError != nil)
        #expect(world.assertions.isEmpty)
    }

    @Test func nextOccurrenceRollsOverToTomorrow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let threePM = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 15)))

        let later = calendar.nextOccurrence(hour: 16, minute: 30, after: threePM)
        #expect(calendar.component(.day, from: later) == 8)
        #expect(calendar.component(.hour, from: later) == 16)

        let earlier = calendar.nextOccurrence(hour: 14, minute: 0, after: threePM)
        #expect(calendar.component(.day, from: earlier) == 9)
        #expect(calendar.component(.hour, from: earlier) == 14)
    }

    // MARK: Battery rules

    @Test func lowBatteryStopsTheSessionAndSaysSo() {
        world.power = PowerSourceState(isOnBattery: true, batteryPercent: 50)
        controller.start(.indefinitely)
        #expect(controller.isActive)

        controller.powerSourceChanged(PowerSourceState(isOnBattery: true, batteryPercent: 19))
        #expect(!controller.isActive)
        #expect(controller.endNote == "Stopped: battery fell below 20%")
        #expect(world.notifications.count == 1)
    }

    @Test func lowBatteryWhilePluggedInIsFine() {
        controller.start(.indefinitely)
        controller.powerSourceChanged(PowerSourceState(isOnBattery: false, batteryPercent: 5))
        #expect(controller.isActive)
    }

    @Test func wontStartOnLowBattery() {
        world.power = PowerSourceState(isOnBattery: true, batteryPercent: 10)
        controller.start(.duration(900))
        #expect(!controller.isActive)
        #expect(controller.startError?.contains("below 20%") == true)
        #expect(world.assertions.isEmpty)
    }

    @Test func lowBatteryRuleCanBeTurnedOff() {
        preferences.stopOnLowBattery = false
        world.power = PowerSourceState(isOnBattery: true, batteryPercent: 10)
        controller.start(.duration(900))
        #expect(controller.isActive)
    }

    @Test func onlyWhilePluggedInStopsWhenUnplugged() {
        preferences.onlyWhilePluggedIn = true
        controller.start(.indefinitely)
        controller.powerSourceChanged(PowerSourceState(isOnBattery: true, batteryPercent: 90))
        #expect(!controller.isActive)
        #expect(controller.endNote == "Stopped: Mac was unplugged")
    }

    @Test func turningOnABatteryRuleMidSessionAppliesItRightAway() {
        world.power = PowerSourceState(isOnBattery: true, batteryPercent: 90)
        controller.start(.indefinitely)
        preferences.onlyWhilePluggedIn = true
        controller.preferencesChanged(.power)
        #expect(!controller.isActive)
    }

    @Test func desktopMacsWithoutABatteryAreNeverStopped() {
        world.power = PowerSourceState(isOnBattery: false, batteryPercent: nil)
        controller.start(.indefinitely)
        controller.powerSourceChanged(PowerSourceState(isOnBattery: false, batteryPercent: nil))
        #expect(controller.isActive)
    }

    // MARK: While an app is running

    @Test func endsWhenTheWatchedAppQuits() {
        let app = WatchedApp(name: "Xcode", pid: 501)
        world.runningPIDs = [501, 777]
        controller.start(.whileRunning(app))
        #expect(world.liveAssertions[0].name == "Treble Keep Awake (while Xcode is running)")

        controller.appTerminated(pid: 777)
        #expect(controller.isActive, "Another app quitting doesn't matter")

        controller.appTerminated(pid: 501)
        #expect(!controller.isActive)
        #expect(controller.endNote == "Stopped: Xcode quit")
        #expect(world.notifications.count == 1)
    }

    @Test func wontWaitForAnAppThatIsntRunning() {
        controller.start(.whileRunning(WatchedApp(name: "Xcode", pid: 501)))
        #expect(!controller.isActive)
        #expect(controller.startError == "Xcode isn't running.")
    }

    // MARK: Display setting

    @Test func changingTheDisplaySettingSwapsTheAssertionWithoutAGap() {
        controller.start(.indefinitely)
        let first = world.assertions[0]

        preferences.keepDisplayOn = true
        controller.preferencesChanged(.display)

        #expect(first.isCancelled)
        #expect(world.liveAssertions.count == 1)
        #expect(world.liveAssertions[0].keepsDisplayOn)
        #expect(controller.isActive)
    }

    @Test func refusedAssertionIsReported() {
        world.refusesAssertions = true
        controller.start(.duration(900))
        #expect(!controller.isActive)
        #expect(controller.startError != nil)
    }

    // MARK: Formatting

    @Test func remainingTimeFormatting() {
        #expect(Format.remaining(30) == "<1m")
        #expect(Format.remaining(60) == "1m")
        #expect(Format.remaining(61) == "2m", "Rounds up, so it never shows 0m while running")
        #expect(Format.remaining(3600) == "1h")
        #expect(Format.remaining(4320) == "1h 12m")
        #expect(Format.choice(0) == "∞")
    }
}

// MARK: - The real power assertion

@MainActor
struct SleepAssertionTests {
    /// Creates a real (harmless, short-lived) macOS assertion and checks it's released.
    @Test func realAssertionIsCreatedAndReleased() throws {
        let assertion = try #require(PowerService.preventSleep(name: "Treble test", keepDisplayOn: false))
        #expect(assertion.isActive)
        assertion.cancel()
        #expect(!assertion.isActive)
        assertion.cancel() // Cancelling twice is safe.
    }

    /// What macOS itself reports, via `pmset -g assertions`.
    @Test func macOSSeesTheAssertionByNameAndThenItsGone() throws {
        let name = "Treble test \(UUID().uuidString.prefix(8))"
        let assertion = try #require(PowerService.preventSleep(name: name, keepDisplayOn: false))
        #expect(try pmsetAssertions().contains(name))

        assertion.cancel()
        #expect(try !pmsetAssertions().contains(name))
    }

    private func pmsetAssertions() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "assertions"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    @Test func powerSourceCanBeRead() {
        let state = PowerService.powerSource
        if let percent = state.batteryPercent {
            #expect((0...100).contains(percent))
        }
    }
}
