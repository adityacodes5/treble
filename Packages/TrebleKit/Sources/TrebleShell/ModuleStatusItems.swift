import AppKit
import Observation
import SwiftUI
import TrebleCore

/// Menu bar items for features the user placed in the menu bar.
///
/// Watches the registry and adds, updates or removes items as features are
/// turned on and off or change their label. Uses plain AppKit labels (symbol +
/// text) rather than SwiftUI views, which keeps the menu bar cheap to redraw.
@MainActor
final class ModuleStatusItems: NSObject {
    private struct Entry {
        let item: NSStatusItem
        let popover: NSPopover
    }

    private let registry: ModuleRegistry
    private var entries: [String: Entry] = [:]

    init(registry: ModuleRegistry) {
        self.registry = registry
    }

    func start() {
        observe()
    }

    /// Re-syncs whenever anything `sync()` reads changes.
    private func observe() {
        withObservationTracking {
            sync()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func sync() {
        var wanted = Set<String>()
        for record in registry.records where record.isEnabled && record.placement.showsMenuBarItem {
            wanted.insert(record.id)
            let entry = entries[record.id] ?? makeEntry(for: record)
            entries[record.id] = entry
            update(entry, for: record)
        }
        for (id, entry) in entries where !wanted.contains(id) {
            entry.popover.close()
            NSStatusBar.system.removeStatusItem(entry.item)
            entries[id] = nil
        }
    }

    private func makeEntry(for record: ModuleRecord) -> Entry {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "treble.\(record.id)"
        item.button?.identifier = NSUserInterfaceItemIdentifier(record.id)
        item.button?.target = self
        item.button?.action = #selector(clicked(_:))

        let popover = NSPopover()
        popover.behavior = .transient
        let hosting = NSHostingController(rootView: ModulePopoverView(record: record, registry: registry))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting

        return Entry(item: item, popover: popover)
    }

    private func update(_ entry: Entry, for record: ModuleRecord) {
        guard let button = entry.item.button else { return }
        let label = record.status.isRunning
            ? record.menuBarLabel ?? MenuBarLabel(symbol: record.type.symbol)
            : MenuBarLabel(symbol: "exclamationmark.triangle")

        if let symbol = label.symbol {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: record.type.name)
            image?.isTemplate = true
            button.image = image
        } else {
            button.image = nil
        }
        button.title = label.text ?? ""
        button.imagePosition = label.text == nil ? .imageOnly : .imageLeading
        button.toolTip = record.type.name
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let id = sender.identifier?.rawValue, let entry = entries[id] else { return }
        if entry.popover.isShown {
            entry.popover.performClose(nil)
        } else {
            entry.popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            entry.popover.contentViewController?.view.window?.makeKey()
        }
    }
}

/// What a feature's own menu bar item shows when clicked.
struct ModulePopoverView: View {
    let record: ModuleRecord
    let registry: ModuleRegistry

    var body: some View {
        Group {
            if record.status.isRunning, let instance = record.instance {
                if let popover = instance.menuBarPopover {
                    popover
                } else if let tile = instance.tile {
                    tile.trebleTile()
                } else {
                    Label(record.type.name, systemImage: record.type.symbol).trebleTile()
                }
            } else {
                StatusTile(record: record, registry: registry).trebleTile()
            }
        }
        .padding(10)
        .frame(width: 300)
    }
}
