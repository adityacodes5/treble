import Foundation

/// A message one part of Treble can broadcast to others without knowing who's listening.
///
/// Event types that several features share live in TrebleCore (or a Service),
/// never in a module, because modules can't import each other.
public protocol TrebleEvent: Sendable {}

/// Delivers events to subscribers on the main thread.
///
/// Modules don't use this directly: they go through `ModuleContext.subscribe`
/// and `ModuleContext.publish`, so their subscriptions are removed
/// automatically when they're turned off.
@MainActor
public final class EventBus {
    public struct Token: Hashable, Sendable {
        fileprivate let id: UUID
        fileprivate let type: ObjectIdentifier
    }

    private var handlers: [ObjectIdentifier: [UUID: @MainActor (any TrebleEvent) -> Void]] = [:]

    public init() {}

    @discardableResult
    public func subscribe<E: TrebleEvent>(
        _ type: E.Type,
        _ handler: @escaping @MainActor (E) -> Void
    ) -> Token {
        let key = ObjectIdentifier(type)
        let id = UUID()
        handlers[key, default: [:]][id] = { event in
            if let event = event as? E { handler(event) }
        }
        return Token(id: id, type: key)
    }

    public func cancel(_ token: Token) {
        handlers[token.type]?[token.id] = nil
        if handlers[token.type]?.isEmpty == true {
            handlers[token.type] = nil
        }
    }

    public func publish<E: TrebleEvent>(_ event: E) {
        // Copy first, so a handler that subscribes or cancels can't disturb the loop.
        guard let current = handlers[ObjectIdentifier(E.self)] else { return }
        for handler in current.values {
            handler(event)
        }
    }

    /// Number of live subscriptions. Used by tests to check nothing leaks.
    var subscriptionCount: Int {
        handlers.values.reduce(0) { $0 + $1.count }
    }
}

// MARK: - Events published by Treble itself

/// The main panel opened or closed. Features can use this to animate only while visible.
public struct PanelVisibilityChanged: TrebleEvent {
    public let isVisible: Bool

    public init(isVisible: Bool) {
        self.isVisible = isVisible
    }
}
