import AppKit

/// Treble has no Dock icon, so its windows would open behind other apps.
/// While Settings or onboarding is open, Treble briefly becomes a regular app
/// (Dock icon, Cmd-Tab, app menu), then goes back to menu bar only.
@MainActor
enum AppActivation {
    private static var openWindows = 0

    static func windowOpened() {
        openWindows += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    static func windowClosed() {
        openWindows = max(0, openWindows - 1)
        if openWindows == 0 {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
