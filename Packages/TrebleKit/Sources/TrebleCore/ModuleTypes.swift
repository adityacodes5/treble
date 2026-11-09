import Foundation

/// What a feature is doing right now. Shown in its tile and in Settings.
public enum ModuleStatus: Equatable, Sendable {
    /// Turned off by the user. Not loaded.
    case off
    /// Working normally.
    case running
    /// Turned on, but waiting for permissions. Not loaded until they're granted.
    case needsPermission(Set<Permission>)
    /// Can't work on this Mac (for example, macOS removed an API it relies on).
    case unavailable(String)
    /// Something went wrong while running. The user can retry.
    case failed(String)

    public var isRunning: Bool { self == .running }
}

/// Where an enabled feature shows up.
public enum Placement: String, CaseIterable, Identifiable, Sendable {
    case panel
    case menuBar
    case both

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .panel: "Panel"
        case .menuBar: "Menu bar"
        case .both: "Both"
        }
    }

    public var showsTile: Bool { self != .menuBar }
    public var showsMenuBarItem: Bool { self != .panel }
}

/// How much room a feature's tile takes in the panel.
public enum TileSize: Sendable {
    /// Half the panel width; two small tiles share a row.
    case small
    /// The full panel width.
    case wide
}

/// What a feature shows in its own menu bar item.
public struct MenuBarLabel: Equatable, Sendable {
    /// An SF Symbol name, or nil for text only.
    public var symbol: String?
    /// Short text next to the symbol, or nil for symbol only.
    public var text: String?

    public init(symbol: String? = nil, text: String? = nil) {
        self.symbol = symbol
        self.text = text
    }
}
