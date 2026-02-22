//
//  QuickshareManagerWindowController.swift
//  Droppy
//
//  Window controller for presenting the Quickshare Manager
//  Matches native Droppy window style (borderless NSPanel, like Onboarding)
//

import AppKit
import SwiftUI

/// Window controller for the Quickshare Manager
final class QuickshareManagerWindowController: NSObject, NSWindowDelegate {
    static let shared = QuickshareManagerWindowController()
    
    private var window: NSPanel?
    private var isClosing = false
    private var deferredTeardownWorkItem: DispatchWorkItem?
    private let deferredTeardownDelay: TimeInterval = 8

    private override init() {
        super.init()
    }
    
    /// Show the Quickshare Manager window
    static func show() {
        shared.showWindow()
    }
    
    private func showWindow() {
        if let window {
            cancelDeferredTeardown()
            NSApp.activate(ignoringOtherApps: true)
            if window.isVisible {
                window.makeKeyAndOrderFront(nil)
            } else {
                AppKitMotion.prepareForPresent(window, initialScale: 0.9)
                window.orderFront(nil)
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    window.makeKeyAndOrderFront(nil)
                }
                AppKitMotion.animateIn(window, initialScale: 0.9, duration: 0.2)
            }
            return
        }

        // Use QuickshareInfoView (the new consolidated UI)
        let contentView = QuickshareInfoView(
            installCount: nil, // Stats optional in standalone manager
            onClose: {
                QuickshareManagerWindowController.hide()
            }
        )
        
        
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.setFrameSize(hostingView.fittingSize) // Use intrinsic size
        
        // Use NSPanel with borderless style (matches Onboarding/UpdateView exactly)
        let newWindow = NSPanel(
            contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        newWindow.titlebarAppearsTransparent = true
        newWindow.titleVisibility = .hidden
        newWindow.backgroundColor = .clear
        newWindow.isOpaque = false
        newWindow.hasShadow = true
        newWindow.isMovableByWindowBackground = true
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        newWindow.contentView = hostingView
        
        // Center on main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = newWindow.frame
            let x = screenFrame.midX - windowFrame.width / 2
            let y = screenFrame.midY - windowFrame.height / 2
            newWindow.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            newWindow.center()
        }
        newWindow.level = .floating
        
        self.window = newWindow
        AppKitMotion.prepareForPresent(newWindow, initialScale: 0.9)
        
        // Bring to front and activate
        newWindow.orderFront(nil)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            newWindow.makeKeyAndOrderFront(nil)
        }
        AppKitMotion.animateIn(newWindow, initialScale: 0.9, duration: 0.24)
        
        HapticFeedback.expand()
    }
    
    /// Hide the Quickshare Manager window
    static func hide() {
        shared.hideWindow()
    }

    private func hideWindow() {
        guard let panel = window, !isClosing else { return }
        cancelDeferredTeardown()
        isClosing = true

        AppKitMotion.animateOut(panel, targetScale: 1.0, duration: 0.15) { [weak self] in
            guard let self else { return }
            panel.orderOut(nil)
            AppKitMotion.resetPresentationState(panel)
            self.isClosing = false
            self.scheduleDeferredTeardown()
        }
    }

    private func scheduleDeferredTeardown() {
        deferredTeardownWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let panel = self.window, !panel.isVisible else { return }
            panel.contentView = nil
            panel.delegate = nil
            self.window = nil
            self.deferredTeardownWorkItem = nil
        }
        deferredTeardownWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + deferredTeardownDelay, execute: workItem)
    }

    private func cancelDeferredTeardown() {
        deferredTeardownWorkItem?.cancel()
        deferredTeardownWorkItem = nil
    }
    
    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideWindow()
        return false
    }
    
    func windowWillClose(_ notification: Notification) {
        window = nil
        isClosing = false
        cancelDeferredTeardown()
    }
}
