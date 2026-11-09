import AppKit

/// Notices when the user may have changed Treble's permissions, without polling.
///
/// macOS has no "permission changed" callback, but it broadcasts a
/// notification whenever the Accessibility list changes, and the user usually
/// switches back to Treble after visiting System Settings. Either one triggers
/// a re-check.
@MainActor
public final class PermissionMonitor {
    private let onChange: @MainActor () -> Void
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var pendingCheck: Task<Void, Never>?

    public init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    public func start() {
        guard observers.isEmpty else { return }

        let distributed = DistributedNotificationCenter.default()
        observers.append((distributed, distributed.addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleCheck() }
        }))

        let local = NotificationCenter.default
        observers.append((local, local.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleCheck() }
        }))
    }

    public func stop() {
        for (center, observer) in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
        pendingCheck?.cancel()
    }

    private func scheduleCheck() {
        // macOS updates its permission database a moment after the notification.
        pendingCheck?.cancel()
        pendingCheck = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.onChange()
        }
    }
}
