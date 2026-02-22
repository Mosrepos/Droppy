//
//  DonateWindowController.swift
//  Droppy
//
//  Created by Codex on 22/02/2026.
//

import Cocoa
import SwiftUI

class DonateWindowController: NSObject, NSWindowDelegate {
    static let shared = DonateWindowController()

    private var window: NSWindow?
    private var isClosing = false
    private var deferredTeardownWorkItem: DispatchWorkItem?
    private let deferredTeardownDelay: TimeInterval = 8

    private override init() {
        super.init()
    }

    func showWindow() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

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

            let donateView = DonateView()
            let hostingView = NSHostingView(rootView: donateView)

            let windowWidth: CGFloat = 420
            let windowHeight: CGFloat = 280

            let newWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )

            newWindow.center()
            newWindow.title = "Support Droppy"
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
            newWindow.contentView = hostingView

            self.window = newWindow
            AppKitMotion.prepareForPresent(newWindow, initialScale: 0.9)

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
