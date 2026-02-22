//
//  LockScreenDisplayContextProvider.swift
//  Droppy
//
//  Centralized lock-screen display context resolver.
//  Pins one deterministic display context for the entire lock session.
//

import AppKit
import CoreGraphics

struct LockScreenDisplayContext {
    let screen: NSScreen
    let frame: NSRect
    let displayID: CGDirectDisplayID
    let identifier: String
    let notchHeight: CGFloat
    let notchWidth: CGFloat
    let centerX: CGFloat
}

@MainActor
final class LockScreenDisplayContextProvider {
    static let shared = LockScreenDisplayContextProvider()

    private(set) var context: LockScreenDisplayContext?
    private var pinnedContext: LockScreenDisplayContext?
    private var screenChangeObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []

    private init() {
        refresh(reason: "init")
        registerObservers()
    }

    deinit {
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { workspaceCenter.removeObserver($0) }
    }

    @discardableResult
    func refresh(reason: String) -> LockScreenDisplayContext? {
        if let pinned = pinnedContext {
            if let updatedScreen = NSScreen.screens.first(where: { $0.displayID == pinned.displayID }) {
                let snapshot = makeContext(for: updatedScreen)
                pinnedContext = snapshot
                context = snapshot
                return snapshot
            }

            // Pinned display disappeared; fall back deterministically.
            if let fallbackScreen = preferredLockScreen() {
                let snapshot = makeContext(for: fallbackScreen)
                pinnedContext = snapshot
                context = snapshot
                return snapshot
            }

            context = nil
            return nil
        }

        guard let screen = preferredLockScreen() else {
            context = nil
            return nil
        }

        let snapshot = makeContext(for: screen)
        context = snapshot
        return snapshot
    }

    func contextSnapshot() -> LockScreenDisplayContext? {
        if let pinnedContext {
            return pinnedContext
        }
        if let context {
            return context
        }
        return refresh(reason: "snapshot-miss")
    }

    @discardableResult
    func beginLockSession() -> LockScreenDisplayContext? {
        let snapshot = refresh(reason: "begin-lock-session")
        pinnedContext = snapshot
        return snapshot
    }

    func endLockSession() {
        pinnedContext = nil
    }

    private func makeContext(for screen: NSScreen) -> LockScreenDisplayContext {
        LockScreenDisplayContext(
            screen: screen,
            frame: screen.frame,
            displayID: screen.displayID,
            identifier: screen.localizedName,
            notchHeight: NotchLayoutConstants.notchHeight(for: screen),
            notchWidth: NotchLayoutConstants.notchWidth(for: screen),
            centerX: screen.notchAlignedCenterX
        )
    }

    private func preferredLockScreen() -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }

        if let builtIn = screens.first(where: { $0.isBuiltIn }) {
            return builtIn
        }

        let primaryDisplayID = CGMainDisplayID()
        if let primary = screens.first(where: { $0.displayID == primaryDisplayID }) {
            return primary
        }

        return screens.first
    }

    private func registerObservers() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh(reason: "screen-parameters")
            }
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let wakeObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh(reason: "screens-did-wake")
            }
        }

        let spaceObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh(reason: "space-changed")
            }
        }

        workspaceObservers = [wakeObserver, spaceObserver]
    }
}
