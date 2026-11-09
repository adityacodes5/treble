import Foundation

/// Something that can be stopped: a timer, an observer, a power assertion.
///
/// Hand one to `ModuleContext.own(_:)` and Treble cancels it automatically
/// when the feature is turned off.
@MainActor
public protocol TrebleCancellable: AnyObject {
    func cancel()
}

/// A cancellable that runs a closure once, the first time it's cancelled.
@MainActor
public final class Cancellation: TrebleCancellable {
    private var onCancel: (@MainActor () -> Void)?

    public init(_ onCancel: @escaping @MainActor () -> Void) {
        self.onCancel = onCancel
    }

    public var isCancelled: Bool { onCancel == nil }

    public func cancel() {
        let action = onCancel
        onCancel = nil
        action?()
    }
}

/// Main-thread timers with tolerance, so macOS can batch wakeups and save energy.
@MainActor
public enum TrebleTimer {
    /// Runs `action` once at `date` (wall-clock time). Cancel to stop it.
    public static func once(
        at date: Date,
        tolerance: TimeInterval,
        _ action: @escaping @MainActor () -> Void
    ) -> Cancellation {
        let timer = Timer(fire: date, interval: 0, repeats: false) { _ in
            MainActor.assumeIsolated { action() }
        }
        timer.tolerance = tolerance
        RunLoop.main.add(timer, forMode: .common)
        return Cancellation { timer.invalidate() }
    }

    /// Runs `action` every `interval` seconds, starting at `start`. Cancel to stop it.
    public static func repeating(
        every interval: TimeInterval,
        from start: Date = Date(),
        tolerance: TimeInterval,
        _ action: @escaping @MainActor () -> Void
    ) -> Cancellation {
        let timer = Timer(fire: start, interval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { action() }
        }
        timer.tolerance = tolerance
        RunLoop.main.add(timer, forMode: .common)
        return Cancellation { timer.invalidate() }
    }
}

public extension NotificationCenter {
    /// Observes a notification on the main thread until the returned value is cancelled.
    @MainActor
    func trebleObserve(
        _ name: Notification.Name,
        object: Any? = nil,
        _ handler: @escaping @MainActor (Notification) -> Void
    ) -> Cancellation {
        let token = addObserver(forName: name, object: object, queue: .main) { notification in
            // Delivered on the main queue, so handing it to main-actor code is safe.
            nonisolated(unsafe) let notification = notification
            MainActor.assumeIsolated { handler(notification) }
        }
        return Cancellation { [weak self] in
            self?.removeObserver(token)
        }
    }
}
