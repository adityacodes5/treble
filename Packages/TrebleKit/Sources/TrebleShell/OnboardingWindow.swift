import AppKit
import SwiftUI
import TrebleCore

/// The "Choose your features" window shown on first launch, like an
/// installer's component list. Reopened from Settings → General.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let registry: ModuleRegistry
    private let onClose: () -> Void
    private var window: NSWindow?

    init(registry: ModuleRegistry, onClose: @escaping () -> Void) {
        self.registry = registry
        self.onClose = onClose
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let view = OnboardingView(registry: registry) { [weak self] in
            self?.window?.close()
        }
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.title = "Welcome to Treble"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(hosting.view.fittingSize)
        window.center()
        self.window = window

        AppActivation.windowOpened()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Closing counts as finishing, so Treble doesn't ask again every launch.
        registry.hasCompletedOnboarding = true
        AppActivation.windowClosed()
        window = nil
        onClose()
    }
}

struct OnboardingView: View {
    let registry: ModuleRegistry
    let onFinish: () -> Void
    @State private var selected: Set<String>

    init(registry: ModuleRegistry, onFinish: @escaping () -> Void) {
        self.registry = registry
        self.onFinish = onFinish
        let firstTime = !registry.hasCompletedOnboarding
        _selected = State(initialValue: Set(registry.records.filter {
            $0.isEnabled || (firstTime && $0.type.enabledByDefault)
        }.map(\.id)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Choose your features")
                    .font(.title.bold())
                Text("Turn on only what you want. Features you leave off don't run at all. You can change this any time in Settings.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(registry.records) { record in
                    Toggle(isOn: Binding(
                        get: { selected.contains(record.id) },
                        set: { isOn in
                            if isOn { selected.insert(record.id) } else { selected.remove(record.id) }
                        }
                    )) {
                        FeatureDescription(type: record.type)
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack {
                Text("\(selected.count) of \(registry.records.count) selected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Continue") {
                    for record in registry.records {
                        registry.setEnabled(selected.contains(record.id), for: record.id)
                    }
                    registry.hasCompletedOnboarding = true
                    onFinish()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }
        }
        .padding(28)
        .padding(.top, 8)
        .frame(width: 480)
    }
}
