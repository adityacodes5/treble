import Foundation

/// A feature's own settings storage.
///
/// Every key is prefixed with the feature's ID ("sleepTimer.fadeSeconds"), so
/// two features can't overwrite each other's settings by accident.
///
/// In SwiftUI, use `key(_:)` and `store` with `@AppStorage`:
///
///     @AppStorage(settings.key("fadeSeconds"), store: settings.store) var fade = 60
@MainActor
public final class ModuleSettings {
    public let namespace: String
    public let store: UserDefaults

    init(namespace: String, store: UserDefaults) {
        self.namespace = namespace
        self.store = store
    }

    /// The full UserDefaults key for one of this feature's settings.
    public func key(_ name: String) -> String {
        "\(namespace).\(name)"
    }

    /// Reads a setting, or returns `defaultValue` if it was never set.
    public func value<T>(_ name: String, default defaultValue: T) -> T {
        store.object(forKey: key(name)) as? T ?? defaultValue
    }

    /// Saves a setting. Pass nil to remove it.
    public func set(_ value: Any?, for name: String) {
        store.set(value, forKey: key(name))
    }

    /// Removes all of this feature's settings, and nobody else's.
    public func reset() {
        let prefix = namespace + "."
        for key in store.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            store.removeObject(forKey: key)
        }
    }
}
