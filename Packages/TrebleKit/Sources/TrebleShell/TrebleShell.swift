import AppKit
import TrebleCore

/// Treble's app shell: the menu bar items, the panel, Settings and onboarding.
///
/// The shell only knows TrebleCore. The app target hands it the list of
/// feature types, so the shell never imports a feature directly.
@MainActor
public final class TrebleShell: NSObject {
    public let registry: ModuleRegistry

    private var mainItem: MainStatusItem?
    private var panel: PanelController?
    private var moduleItems: ModuleStatusItems?
    private var permissionMonitor: PermissionMonitor?
    private lazy var settings = SettingsWindowController(registry: registry, openOnboarding: { [weak self] in
        self?.showOnboarding()
    })
    private var onboarding: OnboardingWindowController?

    public init(modules: [any TrebleModule.Type], store: UserDefaults = .standard) {
        registry = ModuleRegistry(modules: modules, store: store)
        super.init()
    }

    public func start() {
        MainMenu.install(target: self)

        registry.startEnabledModules()

        let panel = PanelController(
            registry: registry,
            openSettings: { [weak self] in self?.showSettings() },
            openFeatures: { [weak self] in self?.showSettings(page: .features) }
        )
        self.panel = panel

        mainItem = MainStatusItem(
            onClick: { [weak panel] button in panel?.toggle(from: button) },
            onSettings: { [weak self] in self?.showSettings() },
            onChooseFeatures: { [weak self] in self?.showOnboarding() }
        )

        let moduleItems = ModuleStatusItems(registry: registry)
        moduleItems.start()
        self.moduleItems = moduleItems

        let monitor = PermissionMonitor { [weak self] in self?.registry.recheckPermissions() }
        monitor.start()
        permissionMonitor = monitor

        if !registry.hasCompletedOnboarding {
            showOnboarding()
        }
    }

    public func stop() {
        permissionMonitor?.stop()
        registry.stopAll()
    }

    // MARK: Windows

    func showSettings(page: SettingsPage = .general) {
        panel?.close()
        settings.show(page: page)
    }

    @objc func openSettingsAction(_ sender: Any?) {
        showSettings()
    }

    func showOnboarding() {
        panel?.close()
        if onboarding == nil {
            onboarding = OnboardingWindowController(registry: registry) { [weak self] in
                self?.onboarding = nil
            }
        }
        onboarding?.show()
    }

    /// Called when the user opens Treble again (for example from Finder) while it's running.
    public func handleReopen() {
        showSettings()
    }
}
