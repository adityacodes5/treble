import SwiftUI
import TrebleCore

/// The panel's content: tiles from enabled features, then a footer.
struct PanelView: View {
    let registry: ModuleRegistry
    let openSettings: () -> Void
    let openFeatures: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            let tiles = registry.records.filter { $0.isEnabled && $0.placement.showsTile }
            if tiles.isEmpty {
                EmptyPanel(openFeatures: openFeatures)
            } else {
                ForEach(TileRow.rows(for: tiles)) { row in
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(row.records) { record in
                            ModuleTileView(record: record, registry: registry)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                SlotView(.panelFooter, registry: registry.slots)
                Spacer(minLength: 0)
                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Treble Settings")
                .accessibilityLabel("Treble Settings")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        }
        .padding(10)
    }
}

/// Groups tiles into rows: wide tiles get a row each, small tiles pair up.
struct TileRow: Identifiable {
    let records: [ModuleRecord]
    var id: String { records.map(\.id).joined(separator: "+") }

    @MainActor
    static func rows(for records: [ModuleRecord]) -> [TileRow] {
        var rows: [TileRow] = []
        var pendingSmall: ModuleRecord?
        for record in records {
            if record.type.tileSize == .wide {
                rows.append(TileRow(records: [record]))
            } else if let first = pendingSmall {
                rows.append(TileRow(records: [first, record]))
                pendingSmall = nil
            } else {
                pendingSmall = record
            }
        }
        if let last = pendingSmall {
            rows.append(TileRow(records: [last]))
        }
        return rows
    }
}

/// One feature's tile, or a status tile when it isn't running.
struct ModuleTileView: View {
    let record: ModuleRecord
    let registry: ModuleRegistry

    var body: some View {
        if record.status.isRunning, let instance = record.instance {
            if let tile = instance.tile {
                tile.trebleTile()
            } else {
                Label(record.type.name, systemImage: record.type.symbol).trebleTile()
            }
        } else {
            StatusTile(record: record, registry: registry).trebleTile()
        }
    }
}

/// Shown instead of a feature's tile when it needs permission, can't run or failed.
struct StatusTile: View {
    let record: ModuleRecord
    let registry: ModuleRegistry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(record.type.name, systemImage: record.type.symbol)
                .font(.headline)
            switch record.status {
            case .needsPermission(let missing):
                Text("Needs \(missing.displayList) permission.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Grant Access") {
                        missing.sorted().forEach { $0.request() }
                    }
                    Button("Open System Settings") {
                        missing.sorted().first?.openSystemSettings()
                    }
                }
                .controlSize(.small)
            case .unavailable(let reason):
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .failed(let reason):
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Try Again") { registry.restart(id: record.id) }
                    .controlSize(.small)
            case .off, .running:
                EmptyView()
            }
        }
    }
}

private struct EmptyPanel: View {
    let openFeatures: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.2x2")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No features turned on")
                .font(.headline)
            Text("Pick the ones you want. Everything else stays off.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Choose Features…", action: openFeatures)
                .controlSize(.small)
        }
        .padding(.vertical, 12)
        .trebleTile()
    }
}
