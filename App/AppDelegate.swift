import AppKit
import TrebleShell

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shell: TrebleShell?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only one Treble at a time (for example, a debug build and an installed copy).
        if let other = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .first(where: { $0 != .current }) {
            other.activate()
            NSApp.terminate(nil)
            return
        }

        let shell = TrebleShell(modules: FeatureList.all)
        shell.start()
        self.shell = shell
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        shell?.handleReopen()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        shell?.stop()
    }
}
