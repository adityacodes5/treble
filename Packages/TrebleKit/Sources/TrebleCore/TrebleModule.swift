import SwiftUI

/// The contract every Treble feature implements.
///
/// A feature ("module") lives in its own Swift package target and may only
/// import TrebleCore (and, later, shared Services). It never imports another
/// module. Everything it needs from the app comes through its `ModuleContext`.
///
/// Lifecycle:
/// 1. The user turns the feature on → Treble checks `permissions`.
/// 2. If they're granted, Treble creates the module with `init(context:)` and calls `start()`.
/// 3. The user turns it off → Treble calls `stop()` and then releases the module.
///
/// Anything handed out by the context (event subscriptions, slot contributions,
/// the menu bar label) is cleaned up by Treble automatically after `stop()`.
/// `stop()` only has to release what the module created itself: timers,
/// system observers, power assertions and so on.
@MainActor
public protocol TrebleModule: AnyObject {
    /// Stable identifier, used for saved settings. Never change it after release.
    static var id: String { get }
    /// Name shown in Settings and on the "Choose your features" screen.
    static var name: String { get }
    /// One short line describing the feature.
    static var summary: String { get }
    /// SF Symbol name for the feature's icon.
    static var symbol: String { get }
    /// macOS permissions the feature can't work without.
    static var permissions: Set<Permission> { get }
    /// Where the feature shows up when first turned on.
    static var defaultPlacement: Placement { get }
    /// Width of the feature's tile in the panel.
    static var tileSize: TileSize { get }
    /// Whether it's ticked by default on the "Choose your features" screen.
    static var enabledByDefault: Bool { get }

    init(context: ModuleContext)

    /// The feature was turned on. Set up observers, timers and so on here.
    func start()
    /// The feature was turned off. Release everything you set up in `start()`.
    func stop()

    /// The tile's content in the panel. Treble draws the tile background around it.
    var tile: AnyView? { get }
    /// Content of the popover shown when clicking the feature's own menu bar
    /// item. Defaults to the tile.
    var menuBarPopover: AnyView? { get }
    /// The feature's page in Settings.
    var settingsView: AnyView? { get }
}

public extension TrebleModule {
    static var permissions: Set<Permission> { [] }
    static var defaultPlacement: Placement { .panel }
    static var tileSize: TileSize { .wide }
    static var enabledByDefault: Bool { permissions.isEmpty }

    var tile: AnyView? { nil }
    var menuBarPopover: AnyView? { nil }
    var settingsView: AnyView? { nil }
}
