import AppKit
import Observation
import SwiftUI
import TrebleCore

enum SettingsPage: Hashable {
    case general
    case features
    case module(String)
    case about
}

@MainActor
@Observable
final class SettingsNavigation {
    var page: SettingsPage? = .general
}

/// The Settings window, laid out like System Settings.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let registry: ModuleRegistry
    private let openOnboarding: () -> Void
    private let navigation = SettingsNavigation()
    private var window: NSWindow?

    init(registry: ModuleRegistry, openOnboarding: @escaping () -> Void) {
        self.registry = registry
        self.openOnboarding = openOnboarding
    }

    func show(page: SettingsPage) {
        navigation.page = page
        let window = window ?? makeWindow()
        self.window = window
        if !window.isVisible {
            AppActivation.windowOpened()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeWindow() -> NSWindow {
        let view = SettingsView(registry: registry, navigation: navigation, openOnboarding: openOnboarding)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Treble Settings"
        window.contentViewController = NSHostingController(rootView: view)
        window.setContentSize(NSSize(width: 720, height: 500))
        window.contentMinSize = NSSize(width: 620, height: 400)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("TrebleSettings")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        AppActivation.windowClosed()
    }
}

struct SettingsView: View {
    let registry: ModuleRegistry
    @Bindable var navigation: SettingsNavigation
    let openOnboarding: () -> Void

    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.page) {
                Section {
                    SidebarRow(title: "General", symbol: "gearshape", color: .gray)
                        .tag(SettingsPage.general)
                    SidebarRow(title: "Features", symbol: "square.grid.2x2", color: .blue)
                        .tag(SettingsPage.features)
                }
                let enabled = registry.records.filter(\.isEnabled)
                if !enabled.isEmpty {
                    Section("Your Features") {
                        ForEach(enabled) { record in
                            SidebarRow(title: record.type.name, symbol: record.type.symbol, color: .accentColor)
                                .tag(SettingsPage.module(record.id))
                        }
                    }
                }
                Section {
                    SidebarRow(title: "About", symbol: "info.circle", color: .gray)
                        .tag(SettingsPage.about)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            detail
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.page ?? .general {
        case .general:
            GeneralSettings(openOnboarding: openOnboarding)
        case .features:
            FeaturesSettings(registry: registry)
        case .module(let id):
            if let record = registry.record(id: id) {
                ModuleSettingsPage(record: record, registry: registry)
            }
        case .about:
            AboutSettings()
        }
    }
}

/// A sidebar row with a colored rounded-square icon, like System Settings.
private struct SidebarRow: View {
    let title: String
    let symbol: String
    let color: Color

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
    }
}

// MARK: - Pages

private struct GeneralSettings: View {
    let openOnboarding: () -> Void
    @State private var launchAtLogin = LaunchAtLogin()

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled || launchAtLogin.needsApproval },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                if launchAtLogin.needsApproval {
                    HStack {
                        Text("Approve Treble in System Settings → Login Items.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") { launchAtLogin.openLoginItemsSettings() }
                    }
                }
                if let error = launchAtLogin.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
            }
            Section {
                LabeledContent("Choose which features are on") {
                    Button("Choose Features…", action: openOnboarding)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
        .onAppear { launchAtLogin.refresh() }
    }
}

private struct FeaturesSettings: View {
    let registry: ModuleRegistry

    var body: some View {
        Form {
            ForEach(registry.records) { record in
                Section {
                    FeatureToggleRow(record: record, registry: registry)
                    if record.isEnabled {
                        Picker("Show in", selection: Binding(
                            get: { record.placement },
                            set: { registry.setPlacement($0, for: record.id) }
                        )) {
                            ForEach(Placement.allCases) { placement in
                                Text(placement.displayName).tag(placement)
                            }
                        }
                        .pickerStyle(.segmented)
                        if !record.status.isRunning {
                            StatusTile(record: record, registry: registry)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Features")
    }
}

/// A feature's name, summary and permissions, with an on/off switch.
struct FeatureToggleRow: View {
    let record: ModuleRecord
    let registry: ModuleRegistry

    var body: some View {
        Toggle(isOn: Binding(
            get: { record.isEnabled },
            set: { registry.setEnabled($0, for: record.id) }
        )) {
            FeatureDescription(type: record.type)
        }
    }
}

struct FeatureDescription: View {
    let type: any TrebleModule.Type

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: type.symbol)
                .font(.title3)
                .frame(width: 24)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(type.name)
                Text(type.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if !type.permissions.isEmpty {
                    Text("Needs: \(type.permissions.displayList)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

private struct ModuleSettingsPage: View {
    let record: ModuleRecord
    let registry: ModuleRegistry

    var body: some View {
        Group {
            if record.status.isRunning, let view = record.instance?.settingsView {
                view
            } else if record.status.isRunning {
                Form {
                    Text("\(record.type.name) has no settings yet.")
                        .foregroundStyle(.secondary)
                }
                .formStyle(.grouped)
            } else {
                Form {
                    StatusTile(record: record, registry: registry)
                }
                .formStyle(.grouped)
            }
        }
        .navigationTitle(record.type.name)
    }
}

private struct AboutSettings: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("Treble").font(.title.bold())
            Text(version).foregroundStyle(.secondary)
            Text("Free and open source. MIT License.\nNo tracking, no accounts.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Link("github.com/adityacodes5/treble", destination: URL(string: "https://github.com/adityacodes5/treble")!)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("About")
    }
}
