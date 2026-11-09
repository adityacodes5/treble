import Foundation
import IOKit.ps
import TrebleCore

/// Where the Mac's power is coming from right now.
public struct PowerSourceState: Equatable, Sendable {
    /// True when running on battery (unplugged).
    public var isOnBattery: Bool
    /// Battery charge from 0 to 100, or nil on Macs without a battery.
    public var batteryPercent: Int?

    public init(isOnBattery: Bool, batteryPercent: Int?) {
        self.isOnBattery = isOnBattery
        self.batteryPercent = batteryPercent
    }

    public var hasBattery: Bool { batteryPercent != nil }

    /// Reads the current state from macOS.
    public static func current() -> PowerSourceState {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return PowerSourceState(isOnBattery: false, batteryPercent: nil)
        }
        let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        let isOnBattery = providing == "Battery Power" // kIOPSBatteryPowerValue

        var percent: Int?
        let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] ?? []
        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                description["Type"] as? String == "InternalBattery", // kIOPSTypeKey, kIOPSInternalBatteryType
                description["Is Present"] as? Bool != false, // kIOPSIsPresentKey
                let current = description["Current Capacity"] as? Int, // kIOPSCurrentCapacityKey
                let maximum = description["Max Capacity"] as? Int, maximum > 0 // kIOPSMaxCapacityKey
            else { continue }
            percent = Int((Double(current) / Double(maximum) * 100).rounded())
        }
        return PowerSourceState(isOnBattery: isOnBattery, batteryPercent: percent)
    }
}

/// Watches for power changes (plugging in, battery level) using macOS's own
/// notifications. Runs only while someone is listening.
@MainActor
final class PowerSourceMonitor {
    static let shared = PowerSourceMonitor()

    private var handlers: [UUID: @MainActor (PowerSourceState) -> Void] = [:]
    private var runLoopSource: CFRunLoopSource?
    private var last: PowerSourceState?

    func observe(_ handler: @escaping @MainActor (PowerSourceState) -> Void) -> Cancellation {
        let id = UUID()
        handlers[id] = handler
        startIfNeeded()
        return Cancellation { [weak self] in
            self?.handlers[id] = nil
            self?.stopIfIdle()
        }
    }

    var isRunning: Bool { runLoopSource != nil }

    private func startIfNeeded() {
        guard runLoopSource == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerSourceMonitor>.fromOpaque(context).takeUnretainedValue()
            // Delivered on the main run loop, where the source was added.
            MainActor.assumeIsolated { monitor.powerChanged() }
        }, context)?.takeRetainedValue() else { return }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
        last = .current()
    }

    private func stopIfIdle() {
        guard handlers.isEmpty, let source = runLoopSource else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = nil
        last = nil
    }

    private func powerChanged() {
        let now = PowerSourceState.current()
        guard now != last else { return }
        last = now
        for handler in handlers.values {
            handler(now)
        }
    }
}
