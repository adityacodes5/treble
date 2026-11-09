import AppKit
import SwiftUI
import TrebleCore

/// The main panel: a floating, Control Center–style window under the menu bar icon.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    static let width: CGFloat = 340

    private let panel: PanelWindow
    private let events: EventBus
    private let hosting: PanelHostingView<AnyView>
    private weak var anchor: NSStatusBarButton?
    private var outsideClickMonitor: Any?
    /// When the panel last closed. Clicking the menu bar icon makes the panel
    /// lose focus (closing it) just before the click arrives, which would
    /// otherwise reopen it straight away.
    private var lastClosed = Date.distantPast

    init(registry: ModuleRegistry, openSettings: @escaping () -> Void, openFeatures: @escaping () -> Void) {
        events = registry.events

        let root = PanelView(registry: registry, openSettings: openSettings, openFeatures: openFeatures)
            .frame(width: Self.width)
        hosting = PanelHostingView(rootView: AnyView(root))
        hosting.sizingOptions = [.intrinsicContentSize]
        panel = PanelWindow(content: hosting)

        super.init()
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.close() }
        // Tiles appearing or disappearing change the content size: resize to fit.
        hosting.onSizeChange = { [weak self] in self?.fitToContent() }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle(from button: NSStatusBarButton) {
        if isVisible {
            close()
        } else if Date().timeIntervalSince(lastClosed) > 0.3 {
            show(from: button)
        }
    }

    func show(from button: NSStatusBarButton) {
        anchor = button
        fitToContent()
        panel.makeKeyAndOrderFront(nil)
        button.highlight(true)

        // Close when the user clicks anywhere outside Treble.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        events.publish(PanelVisibilityChanged(isVisible: true))
    }

    func close() {
        guard isVisible else { return }
        lastClosed = Date()
        panel.orderOut(nil)
        anchor?.highlight(false)
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        events.publish(PanelVisibilityChanged(isVisible: false))
    }

    /// Sizes the panel to its content, keeping the top edge under the menu bar.
    private func fitToContent() {
        let size = hosting.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        if panel.frame.size != size {
            panel.setContentSize(size)
        }
        reposition()
    }

    /// Places the panel just under the menu bar icon, kept fully on screen.
    private func reposition() {
        guard let button = anchor, let buttonWindow = button.window else { return }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let size = panel.frame.size
        let margin: CGFloat = 8

        var x = buttonFrame.maxX - size.width
        x = min(max(x, visible.minX + margin), visible.maxX - size.width - margin)
        let y = buttonFrame.minY - 6 - size.height
        panel.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        close()
    }
}

/// Reports when its SwiftUI content changes size.
final class PanelHostingView<Content: View>: NSHostingView<Content> {
    var onSizeChange: (() -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        // Let SwiftUI finish the update before measuring.
        DispatchQueue.main.async { [weak self] in self?.onSizeChange?() }
    }
}

/// A borderless, non-activating panel (it doesn't steal focus from the app
/// you're using), with Control Center's translucent material and rounded corners.
final class PanelWindow: NSPanel {
    var onCancel: (() -> Void)?

    init(content: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: PanelController.width, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        isMovable = false
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]

        let material = NSVisualEffectView()
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        material.maskImage = Self.roundedMask(radius: 14)

        content.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            content.topAnchor.constraint(equalTo: material.topAnchor),
            content.bottomAnchor.constraint(equalTo: material.bottomAnchor),
        ])
        contentView = material
    }

    override var canBecomeKey: Bool { true }

    /// Esc closes the panel.
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    /// A stretchable rounded-rectangle mask, so corners stay round at any size
    /// and the window shadow follows them.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
