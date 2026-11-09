import AppKit
import ApplicationServices

/// A macOS privacy permission a feature can require.
///
/// Features list what they need in `TrebleModule.permissions`. Treble only asks
/// for a permission when a feature that needs it is turned on.
public enum Permission: String, CaseIterable, Sendable, Codable, Comparable {
    case accessibility
    case screenRecording

    public var displayName: String {
        switch self {
        case .accessibility: "Accessibility"
        case .screenRecording: "Screen Recording"
        }
    }

    /// Whether macOS has granted this permission to Treble right now.
    @MainActor public var isGranted: Bool {
        switch self {
        case .accessibility: AXIsProcessTrusted()
        case .screenRecording: CGPreflightScreenCaptureAccess()
        }
    }

    /// Shows the system's permission prompt (or does nothing if already granted).
    @MainActor public func request() {
        switch self {
        case .accessibility:
            // The string value of kAXTrustedCheckOptionPrompt, used directly to
            // avoid Swift 6 concurrency warnings about the imported global.
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
        }
    }

    /// Opens the matching page in System Settings → Privacy & Security.
    @MainActor public func openSystemSettings() {
        let anchor = switch self {
        case .accessibility: "Privacy_Accessibility"
        case .screenRecording: "Privacy_ScreenCapture"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    public static func < (lhs: Permission, rhs: Permission) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension Set where Element == Permission {
    /// "Accessibility" or "Accessibility and Screen Recording".
    public var displayList: String {
        sorted().map(\.displayName).formatted(.list(type: .and))
    }
}
