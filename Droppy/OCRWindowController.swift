//
//  OCRWindowController.swift
//  Droppy
//
//  Created by Jordy Spruit on 02/01/2026.
//

import AppKit
import SwiftUI
import CoreGraphics

@MainActor
final class OCRWindowController: NSObject, NSWindowDelegate {
    static let shared = OCRWindowController()
    
    private(set) var window: NSWindow?
    private var hostingView: NSHostingView<OCRResultView>?
    private var escapeMonitor: Any?
    private var globalEscapeMonitor: Any?
    private var isClosing = false
    private var deferredTeardownWorkItem: DispatchWorkItem?
    private let deferredTeardownDelay: TimeInterval = 8
    
    private override init() {
        super.init()
    }
    
    func show(with text: String, targetDisplayID: CGDirectDisplayID? = nil) {
        cancelDeferredTeardown()

        let contentView = OCRResultView(text: text) { [weak self] in
            self?.close()
        }

        if let hostingView {
            hostingView.rootView = contentView
        } else {
            let newHostingView = NSHostingView(rootView: contentView)
            self.hostingView = newHostingView
        }

        let panel: NSWindow
        if let existing = window {
            panel = existing
        } else {
            let newWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 400),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )

            newWindow.title = "Extracted Text"
            newWindow.titlebarAppearsTransparent = true
            newWindow.titleVisibility = .hidden
            newWindow.standardWindowButton(.closeButton)?.isHidden = true
            newWindow.standardWindowButton(.miniaturizeButton)?.isHidden = true
            newWindow.standardWindowButton(.zoomButton)?.isHidden = true

            newWindow.isMovableByWindowBackground = true
            newWindow.backgroundColor = .clear
            newWindow.isOpaque = false
            newWindow.hasShadow = true
            newWindow.isReleasedWhenClosed = false
            newWindow.delegate = self

            self.window = newWindow
            panel = newWindow
        }

        if let hostingView {
            panel.contentView = hostingView
        }

        if let screen = resolveScreen(for: targetDisplayID) {
            let visibleFrame = screen.visibleFrame
            let size = panel.frame.size
            let origin = NSPoint(
                x: visibleFrame.midX - (size.width / 2),
                y: visibleFrame.midY - (size.height / 2)
            )
            panel.setFrameOrigin(origin)
        } else {
            panel.center()
        }

        if panel.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            AppKitMotion.prepareForPresent(panel, initialScale: 0.9)

            // Show - use deferred makeKey to avoid NotchWindow conflicts
            panel.orderFront(nil)
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                panel.makeKeyAndOrderFront(nil)
            }
            AppKitMotion.animateIn(panel, initialScale: 0.9, duration: 0.2)
        }

        installEscapeMonitors()
    }

    func presentExtractedText(_ text: String, targetDisplayID: CGDirectDisplayID? = nil) {
        let shouldAutoCopy = UserDefaults.standard.preference(
            AppPreferenceKey.ocrAutoCopyExtractedText,
            default: PreferenceDefault.ocrAutoCopyExtractedText
        )
        let hasVisibleText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if shouldAutoCopy && hasVisibleText {
            close()
            TextCopyFeedback.copyOCRText(text)
        } else {
            show(with: text, targetDisplayID: targetDisplayID)
        }
    }
    
    func close() {
        guard let panel = window, !isClosing else { return }
        cancelDeferredTeardown()
        isClosing = true
        removeEscapeMonitors()

        AppKitMotion.animateOut(panel, targetScale: 0.96, duration: 0.15) { [weak self] in
            panel.orderOut(nil)
            AppKitMotion.resetPresentationState(panel)
            self?.isClosing = false
            self?.scheduleDeferredTeardown()
        }
    }

    private func scheduleDeferredTeardown() {
        deferredTeardownWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let panel = self.window, !panel.isVisible else { return }
            panel.contentView = nil
            panel.delegate = nil
            self.window = nil
            self.hostingView = nil
            self.deferredTeardownWorkItem = nil
        }
        deferredTeardownWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + deferredTeardownDelay, execute: workItem)
    }

    private func cancelDeferredTeardown() {
        deferredTeardownWorkItem?.cancel()
        deferredTeardownWorkItem = nil
    }

    private func resolveScreen(for displayID: CGDirectDisplayID?) -> NSScreen? {
        guard let displayID else {
            return nil
        }

        return NSScreen.screens.first { screen in
            guard let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                return false
            }
            return screenID == displayID
        }
    }

    private func installEscapeMonitors() {
        removeEscapeMonitors()

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            guard let self = self, let panel = self.window, panel.isVisible else { return event }
            self.close()
            return nil
        }

        globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor [weak self] in
                guard let self = self, let panel = self.window, panel.isVisible else { return }
                self.close()
            }
        }
    }

    private func removeEscapeMonitors() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
        if let monitor = globalEscapeMonitor {
            NSEvent.removeMonitor(monitor)
            globalEscapeMonitor = nil
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        close()
        return false
    }

    func windowWillClose(_ notification: Notification) {
        removeEscapeMonitors()
        window = nil
        hostingView = nil
        isClosing = false
        cancelDeferredTeardown()
    }
}
