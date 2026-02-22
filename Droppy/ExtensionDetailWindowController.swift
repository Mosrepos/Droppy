import AppKit
import SwiftUI

@MainActor
final class ExtensionDetailWindowController: NSObject, NSWindowDelegate {
    static let shared = ExtensionDetailWindowController()

    private var panel: NSWindow?
    private var currentPanelID: String?
    private var escapeKeyMonitor: Any?
    private var hasUserAdjustedFrame = false
    private var isAdjustingFrameProgrammatically = false
    private var ignoreMoveEventsUntil = Date.distantPast
    private var deferredTeardownWorkItem: DispatchWorkItem?
    private let deferredTeardownDelay: TimeInterval = 8

    private override init() {
        super.init()
    }

    func present<Content: View>(
        id: String,
        parent: NSWindow?,
        @ViewBuilder content: () -> Content
    ) {
        let panel = ensurePanel()
        cancelDeferredTeardown()
        if currentPanelID != id {
            hasUserAdjustedFrame = false
        }
        let rootView = AnyView(
            content()
                .droppyPanelCloseAction { [weak self] in
                    self?.close()
                }
                .overlay(alignment: .top) {
                    ExtensionPanelWindowDragStrip()
                        .frame(height: 24)
                        .allowsHitTesting(true)
                }
        )

        if let hostingView = panel.contentView as? NSHostingView<AnyView> {
            hostingView.rootView = rootView
        } else {
            panel.contentView = NSHostingView(rootView: rootView)
        }

        if !hasUserAdjustedFrame {
            fitPanelToHostedContent(panel)
        }
        attach(panel: panel, to: parent)
        if !hasUserAdjustedFrame {
            center(panel: panel, over: parent)
        } else {
            centerHorizontally(panel: panel, over: parent)
        }

        currentPanelID = id
        installEscapeMonitorIfNeeded()

        if panel.isVisible {
            panel.orderFront(nil)
            panel.makeKeyAndOrderFront(nil)
        } else {
            AppKitMotion.prepareForPresent(panel, initialScale: 1.0)
            panel.orderFront(nil)
            panel.makeKeyAndOrderFront(nil)
            AppKitMotion.animateIn(panel, initialScale: 1.0, duration: 0.2)
        }

        print("🧩 ExtensionDetailPanel: present id=\(id)")
    }

    func closeIfPresenting(id: String) {
        guard currentPanelID == id else { return }
        close()
    }

    func close() {
        currentPanelID = nil
        removeEscapeMonitor()

        guard let panel else { return }

        if let parent = panel.parent {
            parent.removeChildWindow(panel)
        }

        AppKitMotion.animateOut(panel, targetScale: 1.0, duration: 0.15) {
            panel.orderOut(nil)
            AppKitMotion.resetPresentationState(panel)
            self.scheduleDeferredTeardown()
            print("🧩 ExtensionDetailPanel: close")
        }
    }

    private func scheduleDeferredTeardown() {
        deferredTeardownWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let panel = self.panel, !panel.isVisible else { return }
            panel.contentView = nil
            panel.delegate = nil
            self.panel = nil
            self.hasUserAdjustedFrame = false
            self.currentPanelID = nil
            self.deferredTeardownWorkItem = nil
        }
        deferredTeardownWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + deferredTeardownDelay, execute: workItem)
    }

    private func cancelDeferredTeardown() {
        deferredTeardownWorkItem?.cancel()
        deferredTeardownWorkItem = nil
    }

    private func ensurePanel() -> NSWindow {
        if let panel {
            return panel
        }

        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.title = ""
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        // Restrict dragging to the titlebar/top area so interactive content
        // (for example draggable icons inside extension views) doesn't move the window.
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 420, height: 520)
        panel.delegate = self

        self.panel = panel
        return panel
    }

    private func fitPanelToHostedContent(_ panel: NSWindow) {
        guard let hostingView = panel.contentView as? NSHostingView<AnyView> else { return }
        let fittingSize = hostingView.fittingSize
        guard fittingSize.width > 0, fittingSize.height > 0 else { return }
        isAdjustingFrameProgrammatically = true
        defer { isAdjustingFrameProgrammatically = false }
        panel.setContentSize(fittingSize)
    }

    private func attach(panel: NSWindow, to parent: NSWindow?) {
        if panel.parent !== parent {
            panel.parent?.removeChildWindow(panel)
            parent?.addChildWindow(panel, ordered: .above)
        }

    }

    private func center(panel: NSWindow, over parent: NSWindow?) {
        let targetFrame: NSRect

        if let parent {
            targetFrame = parent.frame
        } else if let screenFrame = NSScreen.main?.visibleFrame {
            targetFrame = screenFrame
        } else {
            targetFrame = panel.frame
        }

        let proposedOrigin = NSPoint(
            x: targetFrame.midX - panel.frame.width / 2,
            y: targetFrame.midY - panel.frame.height / 2
        )
        let origin = clampedOrigin(for: proposedOrigin, panel: panel, parent: parent)
        isAdjustingFrameProgrammatically = true
        ignoreMoveEventsUntil = Date().addingTimeInterval(0.25)
        defer { isAdjustingFrameProgrammatically = false }
        panel.setFrameOrigin(origin)
    }

    private func centerHorizontally(panel: NSWindow, over parent: NSWindow?) {
        let targetFrame: NSRect

        if let parent {
            targetFrame = parent.frame
        } else if let screenFrame = NSScreen.main?.visibleFrame {
            targetFrame = screenFrame
        } else {
            targetFrame = panel.frame
        }

        let proposedOrigin = NSPoint(
            x: targetFrame.midX - panel.frame.width / 2,
            y: panel.frame.origin.y
        )
        let origin = clampedOrigin(for: proposedOrigin, panel: panel, parent: parent)
        isAdjustingFrameProgrammatically = true
        ignoreMoveEventsUntil = Date().addingTimeInterval(0.25)
        defer { isAdjustingFrameProgrammatically = false }
        panel.setFrameOrigin(origin)
    }

    private func clampedOrigin(for proposedOrigin: NSPoint, panel: NSWindow, parent: NSWindow?) -> NSPoint {
        let visibleFrame = parent?.screen?.visibleFrame
            ?? panel.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(origin: .zero, size: panel.frame.size)

        let padding: CGFloat = 12
        let minX = visibleFrame.minX + padding
        let maxX = visibleFrame.maxX - panel.frame.width - padding
        let minY = visibleFrame.minY + padding
        let maxY = visibleFrame.maxY - panel.frame.height - padding

        let x = maxX >= minX ? min(max(proposedOrigin.x, minX), maxX) : visibleFrame.midX - panel.frame.width / 2
        let y = maxY >= minY ? min(max(proposedOrigin.y, minY), maxY) : visibleFrame.midY - panel.frame.height / 2
        return NSPoint(x: x, y: y)
    }

    private func installEscapeMonitorIfNeeded() {
        guard escapeKeyMonitor == nil else { return }

        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard let panel = self.panel, panel.isVisible else { return event }
            guard event.window === panel else { return event }

            if event.keyCode == 53 {
                self.close()
                return nil
            }

            return event
        }
    }

    private func removeEscapeMonitor() {
        guard let escapeKeyMonitor else { return }
        NSEvent.removeMonitor(escapeKeyMonitor)
        self.escapeKeyMonitor = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        close()
        return false
    }

    func windowWillClose(_ notification: Notification) {
        removeEscapeMonitor()
        if notification.object as? NSWindow === panel {
            currentPanelID = nil
            panel = nil
            hasUserAdjustedFrame = false
            cancelDeferredTeardown()
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard notification.object as? NSWindow === panel else { return }
        if Date() <= ignoreMoveEventsUntil {
            return
        }
        guard !isAdjustingFrameProgrammatically else { return }
        guard panel?.isKeyWindow == true else { return }
        guard NSEvent.pressedMouseButtons != 0 else { return }
        hasUserAdjustedFrame = true
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard notification.object as? NSWindow === panel else { return }
        guard !isAdjustingFrameProgrammatically else { return }
        hasUserAdjustedFrame = true
    }
}

private struct ExtensionPanelWindowDragStrip: NSViewRepresentable {
    func makeNSView(context: Context) -> ExtensionPanelWindowDragNSView {
        ExtensionPanelWindowDragNSView()
    }

    func updateNSView(_ nsView: ExtensionPanelWindowDragNSView, context: Context) {}
}

private final class ExtensionPanelWindowDragNSView: NSView {
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        window.performDrag(with: event)
    }
}
