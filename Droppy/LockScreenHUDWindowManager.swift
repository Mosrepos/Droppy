//
//  LockScreenHUDWindowManager.swift
//  Droppy
//
//  Created by Droppy on 07/02/2026.
//  Manages a dedicated, disposable window for the lock screen HUD.
//  This window is delegated to SkyLight for lock screen visibility.
//  The main notch window is NEVER touched — this prevents the "Delegation Stain".
//

import Foundation
import AppKit
import SwiftUI
import Combine
import SkyLightWindow

/// Manages a separate, throwaway window that shows the lock icon on the macOS lock screen.
///
/// Architecture:
/// - Created fresh on each lock event
/// - Delegated to SkyLight space (level 400) for lock screen visibility
/// - Destroyed on unlock — no recovery needed, no interactivity corruption
/// - Main notch window is NEVER delegated, preserving full hover/drag/click
///
/// Follows the same pattern as `LockScreenMediaPanelManager`.
@MainActor
final class LockScreenHUDWindowManager {
    static let shared = LockScreenHUDWindowManager()

#if DEBUG
    private let lockHUDMotionDebugLogs = false
#else
    private let lockHUDMotionDebugLogs = false
#endif
    
    // MARK: - Window State
    private var hudWindow: NSWindow?
    private var hasDelegated = false
    private var hideTask: Task<Void, Never>?
    private var hideTransitionToken = UUID()
    private var configuredContentSize: NSSize = .zero
    private var currentTargetDisplayID: CGDirectDisplayID?
    private var screenChangeObserver: NSObjectProtocol?
    private let surfaceState = LockScreenHUDSurfaceState()
    
    // MARK: - Dimensions
    /// Wing width for battery/lock HUD — must match NotchShelfView.batteryWingWidth exactly
    private let batteryWingWidth: CGFloat = 65
    
    /// Dynamically calculate HUD width to match NotchShelfView.batteryHudWidth exactly
    /// This ensures the lock screen HUD and main notch have identical dimensions
    private func hudWidth(for screen: NSScreen) -> CGFloat {
        let notchWidth = NotchLayoutConstants.notchWidth(for: screen)
        
        // batteryHudWidth = notchWidth + (batteryWingWidth * 2)
        return notchWidth + (batteryWingWidth * 2)
    }

    private init() {
        setupObservers()
        print("LockScreenHUDWindowManager: 🔒 Initialized")
    }

    deinit {
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Public API
    
    /// Create and show the lock HUD window on the lock screen.
    /// Called by `LockScreenManager` when the screen locks.
    @discardableResult
    func showOnLockScreen() -> Bool {
        guard let context = LockScreenDisplayContextProvider.shared.contextSnapshot()
            ?? LockScreenDisplayContextProvider.shared.beginLockSession() else {
            currentTargetDisplayID = nil
            print("LockScreenHUDWindowManager: ⚠️ No screen available")
            return false
        }
        let screen = context.screen

        print("LockScreenHUDWindowManager: 🔒 Showing lock icon on lock screen")

        // If a delayed hide is pending from a prior unlock, cancel it.
        hideTask?.cancel()
        hideTask = nil
        hideTransitionToken = UUID()
        surfaceState.isUnlockCollapseActive = false
        
        // Calculate width dynamically to match main notch
        let currentHudWidth = hudWidth(for: screen)
        let displayChanged = currentTargetDisplayID != context.displayID
        currentTargetDisplayID = context.displayID
        
        // Calculate frame with new width
        let targetFrame = calculateWindowFrame(for: context, width: currentHudWidth)
        
        let window: NSWindow
        let createdFreshWindow: Bool

        if let existingWindow = hudWindow {
            // Reuse existing window (e.g., re-lock without full unlock)
            window = existingWindow
            createdFreshWindow = false
        } else {
            // Create fresh window
            window = createHUDWindow(frame: targetFrame)
            hudWindow = window
            hasDelegated = false
            createdFreshWindow = true
        }
        
        // Ensure lock-screen visibility semantics for this phase.
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        // Update frame for current screen geometry
        window.setFrame(targetFrame, display: true)
        logTopEdgeDrift(windowFrame: targetFrame, context: context, phase: "showOnLockScreen")
        
        // Only rebuild the SwiftUI host when needed to avoid visual resets/flicker.
        let needsContentRebuild =
            window.contentView == nil ||
            displayChanged ||
            abs(configuredContentSize.width - targetFrame.width) > 0.5 ||
            abs(configuredContentSize.height - targetFrame.height) > 0.5

        if needsContentRebuild {
            let layout = HUDLayoutCalculator(screen: screen)
            let notchHeight = layout.notchHeight
            let collapsedNotchWidth = max(1, layout.notchWidth)

            let lockHUDContent = LockScreenHUDWindowContent(
                surfaceState: surfaceState,
                lockWidth: currentHudWidth,
                collapsedWidth: collapsedNotchWidth,
                notchHeight: notchHeight,
                targetScreen: screen,
                animateEntrance: createdFreshWindow
            )

            let hostingView = NSHostingView(rootView: lockHUDContent)
            hostingView.frame = NSRect(origin: .zero, size: targetFrame.size)
            hostingView.autoresizingMask = [.width, .height]
            window.contentView = hostingView
            configuredContentSize = targetFrame.size
        }
        
        // Make content background transparent
        if let content = window.contentView {
            content.wantsLayer = true
            content.layer?.backgroundColor = NSColor.clear.cgColor
        }
        
        // Delegate to SkyLight for lock screen visibility (ONLY this throwaway window)
        if !hasDelegated {
            SkyLightOperator.shared.delegateWindow(window)
            hasDelegated = true
            print("LockScreenHUDWindowManager: ✅ Window delegated to SkyLight space")
        }
        
        // Show window
        if createdFreshWindow {
            AppKitMotion.prepareForPresent(window, initialScale: 1.0)
        }
        window.orderFrontRegardless()
        if createdFreshWindow {
            AppKitMotion.animateIn(window, initialScale: 1.0, duration: 0.2)
        }

        print("LockScreenHUDWindowManager: ✅ Lock icon visible on lock screen")
        return true
    }

    /// Keep the same HUD window visible while transitioning back to desktop, then hide it.
    /// This preserves a single visual surface from lock screen to unlocked desktop.
    func transitionToDesktopAndHide(
        after delay: TimeInterval,
        collapseDuration: TimeInterval,
        onHandoffStart: (() -> Void)? = nil,
        completion: (() -> Void)? = nil
    ) {
        guard let window = hudWindow else {
            onHandoffStart?()
            completion?()
            return
        }

        hideTask?.cancel()
        let transitionToken = UUID()
        hideTransitionToken = transitionToken
        // Keep the exact same delegated surface alive through the unlock morph.
        // Avoid any frame/display retargeting during handoff.
        window.orderFrontRegardless()
        window.alphaValue = 1
        if let context = LockScreenDisplayContextProvider.shared.contextSnapshot() {
            logTopEdgeDrift(windowFrame: window.frame, context: context, phase: "unlock-handoff-start")
        }

        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard self?.hideTransitionToken == transitionToken else { return }

            // Dedicated lock surface remains the single owner through handoff.
            onHandoffStart?()

            // Use wing geometry collapse (same visual family as notch expand/shrink),
            // not opacity fade-out.
            self?.surfaceState.isUnlockCollapseActive = true

            let teardownDelay = max(0.01, collapseDuration)
            try? await Task.sleep(nanoseconds: UInt64(teardownDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard self?.hideTransitionToken == transitionToken else { return }
            guard self?.hudWindow === window else { return }

            self?.hideTask = nil
            self?.hideAndDestroy()
            completion?()
        }
    }
    
    /// Destroy the lock HUD window.
    /// Called by `LockScreenManager` when the user actually unlocks.
    func hideAndDestroy() {
        print("LockScreenHUDWindowManager: 🔓 Destroying lock screen HUD window")

        hideTask?.cancel()
        hideTask = nil
        hideTransitionToken = UUID()
        
        guard let window = hudWindow else {
            print("LockScreenHUDWindowManager: No window to destroy")
            return
        }
        
        // Reset alpha before teardown so reused/recreated windows always start fully visible.
        window.alphaValue = 1
        surfaceState.isUnlockCollapseActive = false

        // Remove from screen
        window.orderOut(nil)
        window.contentView = nil
        
        // Fully destroy — the next lock event will create a fresh window
        // This ensures no SkyLight delegation stain persists
        hudWindow = nil
        hasDelegated = false
        configuredContentSize = .zero
        currentTargetDisplayID = nil
        
        print("LockScreenHUDWindowManager: ✅ Window destroyed")
    }
    
    // MARK: - Private Helpers
    
    private func createHUDWindow(frame: NSRect) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.isMovable = false
        window.hasShadow = false  // No shadow for lock screen icon
        window.ignoresMouseEvents = true  // Lock screen — no interaction needed
        window.animationBehavior = .none
        
        return window
    }

    private func setupObservers() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleScreenGeometryChange()
            }
        }
    }

    private func handleScreenGeometryChange() {
        guard hudWindow != nil else { return }
        switch LockScreenManager.shared.transitionPhase {
        case .locking, .locked:
            break
        case .unlocked, .unlockingHandoff:
            return
        }
        guard let context = LockScreenDisplayContextProvider.shared.contextSnapshot() else { return }
        applyPinnedFrameIfNeeded(using: context)
        print("LockScreenHUDWindowManager: 📐 Realigned lock HUD after screen change")
    }

    var preferredDisplayID: CGDirectDisplayID? {
        currentTargetDisplayID
    }

    var currentWindowFrame: NSRect? {
        hudWindow?.frame
    }
    
    /// Calculate the window frame to align with the physical notch area on the built-in display.
    private func calculateWindowFrame(for context: LockScreenDisplayContext, width: CGFloat) -> NSRect {
        // Notchless built-in Macs report a 0pt physical notch height.
        // Use Dynamic Island height there so lock/unlock HUD remains visible.
        let surfaceHeight = max(context.notchHeight, NotchLayoutConstants.dynamicIslandHeight)

        // Center horizontally on the notch
        let notchCenterX = context.centerX
        let originX = notchCenterX - (width / 2)
        
        // Position at the very top of the screen (notch area)
        let originY = context.frame.maxY - surfaceHeight
        
        return NSRect(x: originX, y: originY, width: width, height: surfaceHeight)
    }

    private func applyPinnedFrameIfNeeded(using context: LockScreenDisplayContext) {
        guard let window = hudWindow else { return }
        let frame = calculateWindowFrame(for: context, width: hudWidth(for: context.screen))
        if abs(window.frame.origin.x - frame.origin.x) > 0.5 ||
            abs(window.frame.origin.y - frame.origin.y) > 0.5 ||
            abs(window.frame.width - frame.width) > 0.5 ||
            abs(window.frame.height - frame.height) > 0.5 {
            window.setFrame(frame, display: true)
        }
        currentTargetDisplayID = context.displayID
        logTopEdgeDrift(windowFrame: window.frame, context: context, phase: "geometry-refresh")
    }

    private func logTopEdgeDrift(windowFrame: NSRect, context: LockScreenDisplayContext, phase: String) {
        guard lockHUDMotionDebugLogs else { return }
        let expectedTop = context.frame.maxY
        let dedicatedDelta = abs(windowFrame.maxY - expectedTop)
        if dedicatedDelta > 0.5 {
            print(
                "LockScreenHUDWindowManager: ⚠️ \(phase) top drift \(String(format: "%.3f", dedicatedDelta))pt "
                    + "(minY=\(String(format: "%.3f", windowFrame.minY)), "
                    + "maxY=\(String(format: "%.3f", windowFrame.maxY)), "
                    + "expectedTop=\(String(format: "%.3f", expectedTop)))"
            )
        } else {
            print(
                "LockScreenHUDWindowManager: \(phase) top delta \(String(format: "%.3f", dedicatedDelta))pt "
                    + "(minY=\(String(format: "%.3f", windowFrame.minY)), "
                    + "maxY=\(String(format: "%.3f", windowFrame.maxY)))"
            )
        }
    }
}

@MainActor
private final class LockScreenHUDSurfaceState: ObservableObject {
    @Published var isUnlockCollapseActive = false
}

private struct LockScreenHUDWindowContent: View {
    @ObservedObject private var lockScreenManager = LockScreenManager.shared
    @ObservedObject var surfaceState: LockScreenHUDSurfaceState

    private enum SurfaceMorphPhase {
        case resting
        case entering
        case collapsing

        var scale: CGFloat {
            switch self {
            case .resting:
                1.0
            case .entering:
                0.96
            case .collapsing:
                0.97
            }
        }

        var blur: CGFloat {
            switch self {
            case .resting:
                0
            case .entering:
                3.2
            case .collapsing:
                2.6
            }
        }

        var opacity: Double {
            switch self {
            case .resting:
                1.0
            case .entering:
                0
            case .collapsing:
                0.9
            }
        }
    }

    let lockWidth: CGFloat
    let collapsedWidth: CGFloat
    let notchHeight: CGFloat
    let targetScreen: NSScreen
    let animateEntrance: Bool

    @State private var visualWidth: CGFloat
    @State private var surfaceMorphPhase: SurfaceMorphPhase = .resting
    @State private var hasPlayedEntranceAnimation = false

    init(
        surfaceState: LockScreenHUDSurfaceState,
        lockWidth: CGFloat,
        collapsedWidth: CGFloat,
        notchHeight: CGFloat,
        targetScreen: NSScreen,
        animateEntrance: Bool
    ) {
        self.surfaceState = surfaceState
        self.lockWidth = lockWidth
        self.collapsedWidth = collapsedWidth
        self.notchHeight = notchHeight
        self.targetScreen = targetScreen
        self.animateEntrance = animateEntrance
        _visualWidth = State(initialValue: animateEntrance ? collapsedWidth : lockWidth)
        _surfaceMorphPhase = State(initialValue: animateEntrance ? .entering : .resting)
    }

    var body: some View {
        ZStack {
            NotchShape(bottomRadius: 16)
                .fill(Color.black)
                .frame(width: visualWidth, height: notchHeight)

            LockScreenHUDView(
                hudWidth: visualWidth,
                targetScreen: targetScreen
            )
            .frame(width: visualWidth, height: notchHeight)
        }
        .scaleEffect(surfaceMorphPhase.scale, anchor: .top)
        .blur(radius: surfaceMorphPhase.blur)
        .opacity(surfaceMorphPhase.opacity)
        .geometryGroup()
        .frame(maxWidth: .infinity, maxHeight: notchHeight, alignment: .top)
        .animation(DroppyAnimation.notchState(for: targetScreen), value: surfaceMorphPhase)
        .onAppear {
            // Match regular HUD behavior: collapse -> widen while also blur/fade resolving
            // on the same element so lock/unlock feels identical to other notch surfaces.
            if animateEntrance && !hasPlayedEntranceAnimation {
                hasPlayedEntranceAnimation = true
                visualWidth = collapsedWidth
                withAnimation(DroppyAnimation.notchState(for: targetScreen)) {
                    visualWidth = lockWidth
                    surfaceMorphPhase = .resting
                }
            } else {
                // Keep a stable lock surface size to avoid tiny handoff ghosts.
                visualWidth = lockWidth
                surfaceMorphPhase = .resting
            }
        }
        .onChange(of: lockScreenManager.isUnlocked) { _, isUnlocked in
            withAnimation(DroppyAnimation.notchState(for: targetScreen)) {
                visualWidth = lockWidth
                if !isUnlocked {
                    surfaceMorphPhase = .resting
                }
            }
        }
        .onChange(of: lockWidth) { _, newLockWidth in
            if !lockScreenManager.isUnlocked {
                withAnimation(DroppyAnimation.notchState(for: targetScreen)) {
                    visualWidth = newLockWidth
                }
            }
        }
        .onChange(of: surfaceState.isUnlockCollapseActive) { _, isActive in
            withAnimation(DroppyAnimation.notchState(for: targetScreen)) {
                if isActive {
                    surfaceMorphPhase = .collapsing
                    visualWidth = collapsedWidth
                } else {
                    surfaceMorphPhase = .resting
                    visualWidth = lockWidth
                }
            }
        }
    }
}
