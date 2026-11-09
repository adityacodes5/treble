import SwiftUI

/// Everything a feature gets from Treble. Handed to `TrebleModule.init(context:)`.
///
/// Whatever a feature receives through its context (subscriptions, slot
/// contributions, its menu bar label, and anything it hands to `own(_:)`) is
/// tracked here and removed automatically when the feature is turned off,
/// even if the feature forgets.
@MainActor
public final class ModuleContext {
    public let moduleID: String
    /// This feature's own settings, namespaced by its ID.
    public let settings: ModuleSettings

    private let events: EventBus
    private let slots: SlotRegistry
    private let onStatus: @MainActor (ModuleStatus) -> Void
    private let onMenuBarLabel: @MainActor (MenuBarLabel?) -> Void

    private var subscriptions: [EventBus.Token] = []
    private var contributions: [UUID] = []
    private var owned: [any TrebleCancellable] = []
    /// False once the feature is turned off. Late calls are then ignored.
    private(set) var isActive = true

    init(
        moduleID: String,
        settings: ModuleSettings,
        events: EventBus,
        slots: SlotRegistry,
        onStatus: @escaping @MainActor (ModuleStatus) -> Void,
        onMenuBarLabel: @escaping @MainActor (MenuBarLabel?) -> Void
    ) {
        self.moduleID = moduleID
        self.settings = settings
        self.events = events
        self.slots = slots
        self.onStatus = onStatus
        self.onMenuBarLabel = onMenuBarLabel
    }

    // MARK: Status and menu bar

    /// Reports what the feature is doing. Treble sets `.running` before
    /// calling `start()`; report `.unavailable` or `.failed` if something's wrong.
    public func setStatus(_ status: ModuleStatus) {
        guard isActive else { return }
        onStatus(status)
    }

    /// Sets what the feature shows in its own menu bar item (if the user put it there).
    public func setMenuBarLabel(_ label: MenuBarLabel?) {
        guard isActive else { return }
        onMenuBarLabel(label)
    }

    // MARK: Events

    /// Broadcasts an event to anyone listening.
    public func publish<E: TrebleEvent>(_ event: E) {
        guard isActive else { return }
        events.publish(event)
    }

    /// Listens for an event until the feature is turned off.
    /// Capture `self` weakly in the handler: `{ [weak self] event in ... }`.
    public func subscribe<E: TrebleEvent>(to type: E.Type, _ handler: @escaping @MainActor (E) -> Void) {
        guard isActive else { return }
        subscriptions.append(events.subscribe(type, handler))
    }

    // MARK: Slots

    /// Adds a piece of UI to a named slot until the feature is turned off.
    public func contribute<V: View>(to slot: SlotID, @ViewBuilder _ view: () -> V) {
        guard isActive else { return }
        contributions.append(slots.add(AnyView(view()), to: slot, from: moduleID))
    }

    // MARK: Owned resources

    /// Hands Treble something to cancel when the feature is turned off:
    /// a timer, an observer, a service subscription. Returns it, so you can
    /// also keep it and cancel it yourself earlier.
    ///
    ///     wakeObserver = context.own(NSWorkspace.shared.notificationCenter.trebleObserve(...))
    @discardableResult
    public func own<C: TrebleCancellable>(_ cancellable: C) -> C {
        if isActive {
            owned.append(cancellable)
        } else {
            cancellable.cancel()
        }
        return cancellable
    }

    // MARK: Teardown

    /// Number of things this feature still holds. Zero after teardown.
    var trackedResourceCount: Int {
        subscriptions.count + contributions.count + owned.count
    }

    /// Called by the registry after `stop()`.
    func tearDown() {
        subscriptions.forEach(events.cancel)
        subscriptions.removeAll()
        contributions.forEach(slots.remove)
        contributions.removeAll()
        owned.forEach { $0.cancel() }
        owned.removeAll()
        onMenuBarLabel(nil)
        isActive = false
    }
}
