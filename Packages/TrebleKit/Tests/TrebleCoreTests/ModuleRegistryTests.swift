import Foundation
import SwiftUI
import Testing
@testable import TrebleCore

// MARK: - Test features

struct Ping: TrebleEvent {}

final class ProbeModule: TrebleModule {
    static let id = "probe"
    static let name = "Probe"
    static let summary = "Test feature"
    static let symbol = "star"

    let context: ModuleContext
    var pings = 0
    var stopped = false

    init(context: ModuleContext) {
        self.context = context
    }

    func start() {
        context.subscribe(to: Ping.self) { [weak self] _ in self?.pings += 1 }
        context.contribute(to: .panelFooter) { Text("probe") }
        context.setMenuBarLabel(MenuBarLabel(symbol: "star", text: "1"))
    }

    func stop() {
        stopped = true
    }
}

/// Deliberately sloppy: captures itself strongly in its handler. Treble's
/// teardown must still release it.
final class LeakyModule: TrebleModule {
    static let id = "leaky"
    static let name = "Leaky"
    static let summary = "Test feature that forgets to clean up"
    static let symbol = "drop"

    let context: ModuleContext
    var pings = 0

    init(context: ModuleContext) {
        self.context = context
    }

    func start() {
        context.subscribe(to: Ping.self) { _ in self.pings += 1 }
    }

    func stop() {}
}

final class NeedsAccessModule: TrebleModule {
    static let id = "needsAccess"
    static let name = "Needs Access"
    static let summary = "Test feature that needs a permission"
    static let symbol = "lock"
    static let permissions: Set<Permission> = [.accessibility]

    init(context: ModuleContext) {}
    func start() {}
    func stop() {}
}

final class UnavailableModule: TrebleModule {
    static let id = "unavailable"
    static let name = "Unavailable"
    static let summary = "Test feature that can't run"
    static let symbol = "xmark"

    let context: ModuleContext
    init(context: ModuleContext) { self.context = context }
    func start() { context.setStatus(.unavailable("Not on this Mac")) }
    func stop() {}
}

/// Stands in for macOS's permission state in tests.
@MainActor
final class AccessSwitch {
    var granted = false
}

// MARK: - Tests

@MainActor
struct ModuleRegistryTests {
    let store: UserDefaults

    init() {
        let suite = "treble.tests.\(UUID().uuidString)"
        store = UserDefaults(suiteName: suite)!
        store.removePersistentDomain(forName: suite)
    }

    @Test func featuresStartOff() {
        let registry = ModuleRegistry(modules: [ProbeModule.self], store: store)
        registry.startEnabledModules()
        let record = registry.record(id: "probe")!
        #expect(!record.isEnabled)
        #expect(record.status == .off)
        #expect(record.instance == nil)
    }

    @Test func enablingStartsTheFeature() {
        let registry = ModuleRegistry(modules: [ProbeModule.self], store: store)
        registry.setEnabled(true, for: "probe")
        let record = registry.record(id: "probe")!
        #expect(record.status == .running)
        #expect(record.instance is ProbeModule)
        #expect(record.menuBarLabel == MenuBarLabel(symbol: "star", text: "1"))
        #expect(registry.slots.contributions(for: .panelFooter).count == 1)
    }

    @Test func disablingLeavesNothingBehind() {
        let registry = ModuleRegistry(modules: [ProbeModule.self], store: store)
        registry.setEnabled(true, for: "probe")
        let record = registry.record(id: "probe")!
        weak let module = record.instance as? ProbeModule
        let context = record.context!
        #expect(module != nil)

        registry.setEnabled(false, for: "probe")

        #expect(module == nil, "The feature should be released")
        #expect(record.status == .off)
        #expect(record.menuBarLabel == nil)
        #expect(registry.events.subscriptionCount == 0)
        #expect(registry.slots.contributionCount == 0)
        #expect(context.trackedResourceCount == 0)
        #expect(!context.isActive)
    }

    @Test func sloppyFeaturesAreStillReleased() {
        let registry = ModuleRegistry(modules: [LeakyModule.self], store: store)
        registry.setEnabled(true, for: "leaky")
        weak let module = registry.record(id: "leaky")!.instance as? LeakyModule
        #expect(module != nil)

        registry.setEnabled(false, for: "leaky")
        #expect(module == nil, "Teardown should break the feature's retain cycle")
    }

    @Test func eventsArriveOnlyWhileEnabled() {
        let registry = ModuleRegistry(modules: [ProbeModule.self], store: store)
        registry.setEnabled(true, for: "probe")
        let module = registry.record(id: "probe")!.instance as! ProbeModule

        registry.events.publish(Ping())
        registry.events.publish(Ping())
        #expect(module.pings == 2)

        registry.setEnabled(false, for: "probe")
        registry.events.publish(Ping())
        #expect(module.pings == 2)
        #expect(module.stopped)
    }

    @Test func choicesAreSaved() {
        let first = ModuleRegistry(modules: [ProbeModule.self], store: store)
        first.setEnabled(true, for: "probe")
        first.setPlacement(.menuBar, for: "probe")
        first.stopAll()

        let second = ModuleRegistry(modules: [ProbeModule.self], store: store)
        let record = second.record(id: "probe")!
        #expect(record.isEnabled)
        #expect(record.placement == .menuBar)
        #expect(record.instance == nil, "Nothing runs until startEnabledModules()")

        second.startEnabledModules()
        #expect(record.status == .running)
    }

    @Test func settingsAreNamespaced() {
        let registry = ModuleRegistry(modules: [ProbeModule.self, LeakyModule.self], store: store)
        registry.setEnabled(true, for: "probe")
        registry.setEnabled(true, for: "leaky")
        let probe = registry.record(id: "probe")!.context!.settings
        let leaky = registry.record(id: "leaky")!.context!.settings

        probe.set(5, for: "count")
        leaky.set(9, for: "count")
        #expect(probe.value("count", default: 0) == 5)
        #expect(leaky.value("count", default: 0) == 9)
        #expect(store.integer(forKey: "probe.count") == 5)

        probe.reset()
        #expect(probe.value("count", default: 0) == 0)
        #expect(leaky.value("count", default: 0) == 9, "Resetting one feature must not touch another")
    }

    @Test func missingPermissionsHoldTheFeatureBack() {
        let access = AccessSwitch()
        let registry = ModuleRegistry(
            modules: [NeedsAccessModule.self],
            store: store,
            permissionCheck: { _ in access.granted }
        )
        registry.setEnabled(true, for: "needsAccess")
        let record = registry.record(id: "needsAccess")!
        #expect(record.status == .needsPermission([.accessibility]))
        #expect(record.instance == nil, "Not loaded until permission is granted")

        access.granted = true
        registry.recheckPermissions()
        #expect(record.status == .running)
        #expect(record.instance != nil)

        access.granted = false
        registry.recheckPermissions()
        #expect(record.status == .needsPermission([.accessibility]))
        #expect(record.instance == nil)
    }

    @Test func featuresCanReportTheyCantRun() {
        let registry = ModuleRegistry(modules: [UnavailableModule.self], store: store)
        registry.setEnabled(true, for: "unavailable")
        #expect(registry.record(id: "unavailable")!.status == .unavailable("Not on this Mac"))
    }

    @Test func lateCallsAfterTeardownAreIgnored() {
        let registry = ModuleRegistry(modules: [ProbeModule.self], store: store)
        registry.setEnabled(true, for: "probe")
        let record = registry.record(id: "probe")!
        let context = record.context!
        registry.setEnabled(false, for: "probe")

        // A stray callback (say, a timer firing late) tries to use the old context.
        context.setMenuBarLabel(MenuBarLabel(text: "stale"))
        context.subscribe(to: Ping.self) { _ in }
        context.contribute(to: .panelFooter) { Text("stale") }

        #expect(record.menuBarLabel == nil)
        #expect(registry.events.subscriptionCount == 0)
        #expect(registry.slots.contributionCount == 0)
    }
}

@MainActor
struct EventBusTests {
    @Test func deliversOnlyMatchingTypes() {
        struct Other: TrebleEvent {}
        let bus = EventBus()
        var pings = 0
        bus.subscribe(Ping.self) { _ in pings += 1 }
        bus.publish(Other())
        bus.publish(Ping())
        #expect(pings == 1)
    }

    @Test func cancelStopsDelivery() {
        let bus = EventBus()
        var pings = 0
        let token = bus.subscribe(Ping.self) { _ in pings += 1 }
        bus.cancel(token)
        bus.publish(Ping())
        #expect(pings == 0)
        #expect(bus.subscriptionCount == 0)
    }
}
