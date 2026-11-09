import Observation
import SwiftUI
import TrebleCore

/// A demo feature that exercises every part of the module contract: a tile,
/// its own menu bar item, a settings page, saved settings, an event
/// subscription and a slot contribution. Debug builds only.
///
/// Copy this folder as the starting point for a new feature
/// (see docs/ADDING_A_MODULE.md).
public final class SampleModule: TrebleModule {
    public static let id = "sample"
    public static let name = "Sample"
    public static let summary = "A demo feature for testing Treble's plumbing"
    public static let symbol = "puzzlepiece.extension"
    public static let defaultPlacement: Placement = .both
    public static let tileSize: TileSize = .wide
    public static var enabledByDefault: Bool { false }

    private let context: ModuleContext
    private let model = SampleModel()

    public init(context: ModuleContext) {
        self.context = context
    }

    public func start() {
        // Saved settings are namespaced: this reads "sample.count".
        model.count = context.settings.value("count", default: 0)
        model.showsCount = context.settings.value("showsCount", default: true)

        // Events: count how often the panel opens. Removed automatically on stop.
        context.subscribe(to: PanelVisibilityChanged.self) { [weak self] event in
            if event.isVisible { self?.model.panelOpens += 1 }
        }

        // Slots: put a small label in the panel footer. Removed automatically on stop.
        context.contribute(to: .panelFooter) {
            Text("Sample on")
        }

        updateMenuBarLabel()
    }

    public func stop() {
        // Nothing to release: this feature creates no timers or observers of its own.
    }

    public var tile: AnyView? {
        AnyView(SampleTile(model: model, onTap: { [weak self] in self?.increment() }))
    }

    public var settingsView: AnyView? {
        AnyView(SampleSettings(
            model: model,
            onShowsCountChange: { [weak self] in self?.setShowsCount($0) },
            onReset: { [weak self] in self?.reset() }
        ))
    }

    // MARK: Actions

    private func increment() {
        model.count += 1
        context.settings.set(model.count, for: "count")
        updateMenuBarLabel()
    }

    private func setShowsCount(_ shows: Bool) {
        model.showsCount = shows
        context.settings.set(shows, for: "showsCount")
        updateMenuBarLabel()
    }

    private func reset() {
        context.settings.reset()
        model.count = 0
        model.showsCount = true
        updateMenuBarLabel()
    }

    private func updateMenuBarLabel() {
        context.setMenuBarLabel(MenuBarLabel(
            symbol: Self.symbol,
            text: model.showsCount ? "\(model.count)" : nil
        ))
    }
}

@MainActor
@Observable
final class SampleModel {
    var count = 0
    var showsCount = true
    var panelOpens = 0
}

private struct SampleTile: View {
    let model: SampleModel
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onTap) {
                TileToggleIcon("plus", isOn: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add one")

            VStack(alignment: .leading, spacing: 2) {
                Text("Count: \(model.count)")
                    .font(.headline)
                Text("Panel opened \(model.panelOpens) times")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SampleSettings: View {
    let model: SampleModel
    let onShowsCountChange: (Bool) -> Void
    let onReset: () -> Void

    var body: some View {
        Form {
            Section {
                Toggle("Show count in the menu bar", isOn: Binding(
                    get: { model.showsCount },
                    set: { onShowsCountChange($0) }
                ))
                LabeledContent("Count", value: "\(model.count)")
            }
            Section {
                Button("Reset Sample's settings", role: .destructive, action: onReset)
            }
        }
        .formStyle(.grouped)
    }
}
