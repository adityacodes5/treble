import AppKit
import PowerService
import SwiftUI
import TrebleCore

/// Keep Awake: stop your Mac sleeping for a while.
///
/// This file is the glue between Treble and the controller: it starts system
/// observers only while a session is running, and keeps the menu bar icon current.
public final class KeepAwakeModule: TrebleModule {
    public static let id = "keepAwake"
    public static let name = "Keep Awake"
    public static let summary = "Stop your Mac sleeping for a while"
    public static let symbol = "cup.and.saucer"
    public static let defaultPlacement: Placement = .both
    public static let tileSize: TileSize = .wide

    private let context: ModuleContext
    private let controller: KeepAwakeController
    /// System observers, alive only while a session runs.
    private var sessionObservers: [Cancellation] = []
    /// Updates the menu bar countdown once a minute, only when it's shown.
    private var menuBarTicker: Cancellation?

    public init(context: ModuleContext) {
        self.context = context
        let preferences = KeepAwakePreferences(settings: context.settings)
        controller = KeepAwakeController(preferences: preferences, environment: .live)
    }

    public func start() {
        controller.onSessionChange = { [weak self] in self?.sessionChanged() }
        controller.preferences.onChange = { [weak self] change in
            self?.controller.preferencesChanged(change)
            self?.updateMenuBar()
        }
        updateMenuBar()
    }

    public func stop() {
        controller.stop(.user)
        stopSessionObservers()
        menuBarTicker?.cancel()
        menuBarTicker = nil
    }

    public var tile: AnyView? {
        AnyView(KeepAwakeTile(controller: controller))
    }

    public var settingsView: AnyView? {
        AnyView(KeepAwakeSettings(preferences: controller.preferences))
    }

    // MARK: Session changes

    private func sessionChanged() {
        if controller.isActive {
            startSessionObservers()
        } else {
            stopSessionObservers()
        }
        updateMenuBar()
    }

    private func startSessionObservers() {
        stopSessionObservers()
        let workspace = NSWorkspace.shared.notificationCenter

        // Wall-clock end times survive sleep and clock changes.
        sessionObservers.append(workspace.trebleObserve(NSWorkspace.didWakeNotification) { [weak self] _ in
            self?.controller.refreshTiming()
            self?.updateMenuBar()
        })
        sessionObservers.append(NotificationCenter.default.trebleObserve(.NSSystemClockDidChange) { [weak self] _ in
            self?.controller.refreshTiming()
            self?.updateMenuBar()
        })

        // Battery rules.
        sessionObservers.append(PowerService.observePowerSource { [weak self] state in
            self?.controller.powerSourceChanged(state)
        })

        // "While an app is running".
        if case .whileRunning? = controller.session?.mode {
            sessionObservers.append(workspace.trebleObserve(NSWorkspace.didTerminateApplicationNotification) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.controller.appTerminated(pid: app.processIdentifier)
            })
        }

        // If the feature is turned off mid-session, Treble cancels these too.
        sessionObservers.forEach { context.own($0) }
    }

    private func stopSessionObservers() {
        sessionObservers.forEach { $0.cancel() }
        sessionObservers.removeAll()
    }

    // MARK: Menu bar

    private func updateMenuBar() {
        let session = controller.session
        var text: String?
        if controller.preferences.showTimeInMenuBar, let endDate = session?.endDate {
            text = Format.remaining(endDate.timeIntervalSinceNow)
        }
        context.setMenuBarLabel(MenuBarLabel(
            symbol: session == nil ? "cup.and.saucer" : "cup.and.saucer.fill",
            text: text
        ))

        // Tick once a minute only while a countdown is actually visible.
        let needsTicker = text != nil
        if needsTicker, menuBarTicker == nil {
            menuBarTicker = context.own(TrebleTimer.repeating(
                every: 60,
                from: Date().addingTimeInterval(60),
                tolerance: 5
            ) { [weak self] in
                self?.updateMenuBar()
            })
        } else if !needsTicker {
            menuBarTicker?.cancel()
            menuBarTicker = nil
        }
    }
}
