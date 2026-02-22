//
//  UpdateWindowController.swift
//  Droppy
//
//  Created by Jordy Spruit on 04/01/2026.
//

import Cocoa
import SwiftUI

class UpdateWindowController: NSObject, NSWindowDelegate {
    static let shared = UpdateWindowController()
    
    /// The update window
    private var window: NSWindow?
    private var isClosing = false
    private var deferredTeardownWorkItem: DispatchWorkItem?
    private let deferredTeardownDelay: TimeInterval = 8
    
    private override init() {
        super.init()
    }
    
    /// Shows the update window, creating it if necessary
    func showWindow() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // If window already exists, just bring it to front
            if let window = self.window {
                self.cancelDeferredTeardown()
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
            
            // Create the SwiftUI view
            let updateView = UpdateView()

            let hostingView = NSHostingView(rootView: updateView)
            
            // Compact window size - height determined by content
            let windowWidth: CGFloat = 400
            let windowHeight: CGFloat = 150 // Initial size, will adjust to content
            
            // Create the window - borderless style without traffic lights
            let newWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            
            newWindow.center()
            newWindow.title = "Check for Updates"
            newWindow.titlebarAppearsTransparent = true
            newWindow.titleVisibility = .hidden
            
            // Hide traffic lights
            newWindow.standardWindowButton(.closeButton)?.isHidden = true
            newWindow.standardWindowButton(.miniaturizeButton)?.isHidden = true
            newWindow.standardWindowButton(.zoomButton)?.isHidden = true
            
            // Configure background and appearance
            newWindow.isMovableByWindowBackground = true
            newWindow.backgroundColor = .clear
            newWindow.isOpaque = false
            newWindow.hasShadow = true
            newWindow.isReleasedWhenClosed = false
            
            newWindow.delegate = self
            newWindow.contentView = hostingView
            
            self.window = newWindow
            AppKitMotion.prepareForPresent(newWindow, initialScale: 0.9)
            
            // Bring to front and activate
            newWindow.orderFront(nil)
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                newWindow.makeKeyAndOrderFront(nil)
            }
            AppKitMotion.animateIn(newWindow, initialScale: 0.9, duration: 0.24)
        }
    }
    
    func closeWindow() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.window, !self.isClosing else { return }
            self.cancelDeferredTeardown()
            self.isClosing = true
            AppKitMotion.animateOut(panel, targetScale: 1.0, duration: 0.15) { [weak self] in
                panel.orderOut(nil)
                AppKitMotion.resetPresentationState(panel)
                self?.isClosing = false
                self?.scheduleDeferredTeardown()
            }
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
        if isClosing {
            return true
        }
        closeWindow()
        return false
    }
    
    func windowWillClose(_ notification: Notification) {
        window = nil
        isClosing = false
        cancelDeferredTeardown()
    }
}
