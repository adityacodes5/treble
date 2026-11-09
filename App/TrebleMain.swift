import AppKit

@main
@MainActor
enum TrebleMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // The delegate property is weak; keep ours alive for the app's lifetime.
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
