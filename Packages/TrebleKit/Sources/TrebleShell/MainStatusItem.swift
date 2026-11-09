import AppKit

/// Treble's own menu bar icon. Left-click opens the panel; right-click
/// (or Control-click) shows a small menu.
@MainActor
final class MainStatusItem: NSObject {
    private let item: NSStatusItem
    private let onClick: (NSStatusBarButton) -> Void
    private let onSettings: () -> Void
    private let onChooseFeatures: () -> Void

    init(
        onClick: @escaping (NSStatusBarButton) -> Void,
        onSettings: @escaping () -> Void,
        onChooseFeatures: @escaping () -> Void
    ) {
        self.onClick = onClick
        self.onSettings = onSettings
        self.onChooseFeatures = onChooseFeatures
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        // Lets macOS remember where the user Cmd-dragged the icon to.
        item.autosaveName = "treble.main"

        if let button = item.button {
            let image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Treble")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            onClick(sender)
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(settingsAction), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Choose Features…", action: #selector(chooseFeaturesAction), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Treble", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Attach the menu just for this click, so left-click keeps opening the panel.
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func settingsAction() { onSettings() }
    @objc private func chooseFeaturesAction() { onChooseFeatures() }
}
