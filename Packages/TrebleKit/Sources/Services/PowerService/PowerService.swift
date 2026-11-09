import Foundation
import TrebleCore

/// Treble's single doorway to macOS power management: keeping the Mac awake
/// and watching the power source. Shared by Keep Awake and (later) Sleep Timer.
@MainActor
public enum PowerService {
    /// Asks macOS to stay awake until the returned assertion is cancelled.
    ///
    /// - Parameters:
    ///   - name: Shown in `pmset -g assertions`, for example "Treble Keep Awake (until 3:00 PM)".
    ///   - keepDisplayOn: Also keep the screen on. When false, the screen can
    ///     sleep while the Mac keeps working, which saves battery.
    /// - Returns: nil if macOS refused.
    public static func preventSleep(name: String, keepDisplayOn: Bool) -> SleepAssertion? {
        SleepAssertion(name: name, keepsDisplayOn: keepDisplayOn)
    }

    /// The power source right now.
    public static var powerSource: PowerSourceState {
        .current()
    }

    /// Calls `handler` whenever the power source or battery level changes,
    /// until the returned value is cancelled. Costs nothing while no one is observing.
    public static func observePowerSource(
        _ handler: @escaping @MainActor (PowerSourceState) -> Void
    ) -> Cancellation {
        PowerSourceMonitor.shared.observe(handler)
    }
}
