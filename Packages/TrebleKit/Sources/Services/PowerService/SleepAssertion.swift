import Foundation
import IOKit.pwr_mgt
import TrebleCore

/// A live request to macOS: "please don't sleep right now".
///
/// Released when you call `cancel()`, when it's deallocated, or (by macOS)
/// when Treble quits or crashes, so the Mac can never get stuck awake.
///
/// Shows up in Terminal under `pmset -g assertions` with its name.
public final class SleepAssertion: TrebleCancellable, @unchecked Sendable {
    public let name: String
    public let keepsDisplayOn: Bool

    // Guarded by `lock`; IOKit's release call is thread-safe, which lets deinit release too.
    nonisolated private let lock = NSLock()
    nonisolated(unsafe) private var assertionID: IOPMAssertionID?

    /// Returns nil if macOS refuses the request.
    init?(name: String, keepsDisplayOn: Bool) {
        // The C header defines these as CFSTR macros, which Swift can't import.
        let type = keepsDisplayOn ? "PreventUserIdleDisplaySleep" : "PreventUserIdleSystemSleep"
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            name as CFString,
            &id
        )
        guard result == kIOReturnSuccess else { return nil }
        self.name = name
        self.keepsDisplayOn = keepsDisplayOn
        self.assertionID = id
    }

    nonisolated public var isActive: Bool {
        lock.withLock { assertionID != nil }
    }

    public func cancel() {
        release()
    }

    deinit {
        release()
    }

    nonisolated private func release() {
        let id: IOPMAssertionID? = lock.withLock {
            defer { assertionID = nil }
            return assertionID
        }
        if let id {
            IOPMAssertionRelease(id)
        }
    }
}
