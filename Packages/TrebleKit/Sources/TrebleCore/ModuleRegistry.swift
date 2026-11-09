import Foundation
import Observation

/// One feature's entry in the registry: its type, saved choices and live state.
@MainActor
@Observable
public final class ModuleRecord: Identifiable {
    public nonisolated let id: String
    public let type: any TrebleModule.Type

    public internal(set) var isEnabled: Bool
    public internal(set) var placement: Placement
    public internal(set) var status: ModuleStatus = .off
    public internal(set) var menuBarLabel: MenuBarLabel?
    /// The live feature. Nil whenever it isn't running.
    public internal(set) var instance: (any TrebleModule)?

    @ObservationIgnored var context: ModuleContext?

    init(type: any TrebleModule.Type, isEnabled: Bool, placement: Placement) {
        self.id = type.id
        self.type = type
        self.isEnabled = isEnabled
        self.placement = placement
    }
}

/// Knows every feature compiled into the app, and turns them on and off.
@MainActor
@Observable
public final class ModuleRegistry {
    public private(set) var records: [ModuleRecord]

    @ObservationIgnored public let events: EventBus
    @ObservationIgnored public let slots: SlotRegistry
    @ObservationIgnored private let store: UserDefaults
    @ObservationIgnored private let isGranted: @MainActor (Permission) -> Bool

    /// - Parameters:
    ///   - modules: Every feature type compiled into the app.
    ///   - store: Where choices are saved. Tests pass a throwaway suite.
    ///   - permissionCheck: Overridable for tests. Defaults to asking macOS.
    public init(
        modules: [any TrebleModule.Type],
        store: UserDefaults = .standard,
        permissionCheck: (@MainActor (Permission) -> Bool)? = nil
    ) {
        // A closure, not `map(\.id)`: key paths to static members of metatypes
        // crash the Swift 6.2 compiler.
        let ids = modules.map { $0.id }
        precondition(Set(ids).count == ids.count, "Two features share an ID: \(ids)")

        self.events = EventBus()
        self.slots = SlotRegistry()
        self.store = store
        self.isGranted = permissionCheck ?? { $0.isGranted }
        self.records = modules.map { type in
            ModuleRecord(
                type: type,
                isEnabled: store.object(forKey: Keys.enabled(type.id)) as? Bool ?? false,
                placement: (store.string(forKey: Keys.placement(type.id)))
                    .flatMap(Placement.init(rawValue:)) ?? type.defaultPlacement
            )
        }
    }

    // MARK: Reading

    public func record(id: String) -> ModuleRecord? {
        records.first { $0.id == id }
    }

    public var hasCompletedOnboarding: Bool {
        get { store.bool(forKey: Keys.onboardingComplete) }
        set { store.set(newValue, forKey: Keys.onboardingComplete) }
    }

    // MARK: Changing

    /// Starts every feature the user turned on. Call once at launch.
    public func startEnabledModules() {
        for record in records where record.isEnabled {
            activate(record)
        }
    }

    public func setEnabled(_ enabled: Bool, for id: String) {
        guard let record = record(id: id), record.isEnabled != enabled else { return }
        record.isEnabled = enabled
        store.set(enabled, forKey: Keys.enabled(id))
        if enabled {
            activate(record)
        } else {
            deactivate(record)
        }
    }

    public func setPlacement(_ placement: Placement, for id: String) {
        guard let record = record(id: id) else { return }
        record.placement = placement
        store.set(placement.rawValue, forKey: Keys.placement(id))
    }

    /// Re-checks permissions after the user may have changed them in System
    /// Settings: starts features that were waiting, stops ones that lost access.
    public func recheckPermissions() {
        for record in records where record.isEnabled {
            let missing = missingPermissions(for: record.type)
            switch record.status {
            case .needsPermission where missing.isEmpty:
                activate(record)
            case .running where !missing.isEmpty:
                deactivate(record)
                record.status = .needsPermission(missing)
            case .needsPermission(let old) where old != missing:
                record.status = .needsPermission(missing)
            default:
                break
            }
        }
    }

    /// Restarts a feature, for example after it reported `.failed`.
    public func restart(id: String) {
        guard let record = record(id: id), record.isEnabled else { return }
        deactivate(record)
        activate(record)
    }

    /// Stops every running feature. Call when the app quits.
    public func stopAll() {
        for record in records where record.instance != nil {
            deactivate(record)
        }
    }

    // MARK: Lifecycle

    private func missingPermissions(for type: any TrebleModule.Type) -> Set<Permission> {
        type.permissions.filter { !isGranted($0) }
    }

    private func activate(_ record: ModuleRecord) {
        guard record.instance == nil else { return }

        let missing = missingPermissions(for: record.type)
        guard missing.isEmpty else {
            record.status = .needsPermission(missing)
            return
        }

        let context = ModuleContext(
            moduleID: record.id,
            settings: ModuleSettings(namespace: record.id, store: store),
            events: events,
            slots: slots,
            onStatus: { [weak record] in record?.status = $0 },
            onMenuBarLabel: { [weak record] in record?.menuBarLabel = $0 }
        )
        record.context = context
        record.status = .running

        let module = record.type.init(context: context)
        record.instance = module
        module.start()
    }

    private func deactivate(_ record: ModuleRecord) {
        record.instance?.stop()
        record.context?.tearDown()
        record.instance = nil
        record.context = nil
        record.menuBarLabel = nil
        record.status = .off
    }

    private enum Keys {
        static let onboardingComplete = "treble.onboardingComplete"
        static func enabled(_ id: String) -> String { "treble.enabled.\(id)" }
        static func placement(_ id: String) -> String { "treble.placement.\(id)" }
    }
}
