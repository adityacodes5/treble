import AppKit
import Carbon

/// Talks to music apps through AppleScript, for controls, position and artwork.
///
/// Two rules keep this safe:
/// - **Never launches an app.** Scripts only run if the app is already open,
///   and each script re-checks `is running` itself.
/// - **Never hangs Treble.** Every script has a 2-second timeout.
///
/// The first control request shows macOS's "Allow Treble to control Spotify"
/// prompt. Treble checks quietly first and only asks when the user presses a control.
@MainActor
enum AppleScripting {
    private static var compiled: [String: NSAppleScript] = [:]

    static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Runs a script against `bundleID`. Returns nil if the app isn't open or the script fails.
    /// `body` is the inside of a `tell application` block.
    static func run(_ body: String, in bundleID: String) -> NSAppleEventDescriptor? {
        guard isRunning(bundleID) else { return nil }
        let source = """
        if application id "\(bundleID)" is running then
            with timeout of 2 seconds
                tell application id "\(bundleID)"
                    \(body)
                end tell
            end timeout
        end if
        """
        let script = compiled[source] ?? {
            let script = NSAppleScript(source: source)
            compiled[source] = script
            return script
        }()
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        return error == nil ? result : nil
    }

    /// Checks whether Treble may control `bundleID`. With `ask: true`, shows
    /// the macOS prompt if the user hasn't decided yet (and waits for the answer).
    nonisolated static func access(for bundleID: String, ask: Bool) async -> ControlAccess {
        await Task.detached(priority: .userInitiated) {
            let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
            guard let desc = target.aeDesc else { return ControlAccess.unknown }
            let status = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask)
            switch Int(status) {
            case Int(noErr): return .granted
            case errAEEventNotPermitted: return .denied
            case errAEEventWouldRequireUserConsent: return .notDetermined
            case procNotFound: return .appNotRunning
            default: return .unknown
            }
        }.value
    }

    /// Opens System Settings → Privacy & Security → Automation.
    static func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}

extension NSAppleEventDescriptor {
    /// Items of a returned AppleScript list (AppleScript counts from 1).
    var listItems: [NSAppleEventDescriptor] {
        guard numberOfItems > 0 else { return [] }
        return (1...numberOfItems).compactMap { atIndex($0) }
    }
}
