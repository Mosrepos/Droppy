//
//  LockScreenManager.swift
//  Droppy
//
//  Created by Droppy on 13/01/2026.
//  Detects MacBook lid open/close (screen lock/unlock) events
//

import Foundation
import AppKit
import Combine
import SwiftUI

/// Manages screen lock/unlock detection for HUD display
/// Uses NSWorkspace notifications to detect when screens sleep/wake
class LockScreenManager: ObservableObject {
    static let shared = LockScreenManager()

    enum LockTransitionPhase: Equatable {
        case unlocked
        case locking
        case locked
        case unlockingHandoff
    }

    enum TransitionTiming {
        static let lockExpand: TimeInterval = 0.45
        static let unlockCollapse: TimeInterval = 0.82
    }
    
    /// Current state: true = unlocked (awake), false = locked (asleep)
    @Published private(set) var isUnlocked: Bool = true
    
    /// Timestamp of last state change (triggers HUD)
    @Published private(set) var lastChangeAt: Date = .distantPast
    
    /// The event that triggered the last change
    @Published private(set) var lastEvent: LockEvent = .none

    /// True while the dedicated lock-screen HUD window is the active visual surface.
    /// Used to suppress duplicate inline notch lock HUD rendering during lock/unlock handoff.
    @Published private(set) var isDedicatedHUDActive: Bool = false

    /// Explicit lock/unlock motion phase for deterministic cross-surface handoff behavior.
    @Published private(set) var transitionPhase: LockTransitionPhase = .unlocked
    
    /// Duration the HUD should stay visible
    let visibleDuration: TimeInterval = 2.5
    
    /// Lock event types
    enum LockEvent {
        case none
        case locked    // Screen went to sleep / lid closed
        case unlocked  // Screen woke up / lid opened
    }
    
    /// Whether observers are currently active
    private var isEnabled = false

    private var isLockScreenHUDEnabled: Bool {
        UserDefaults.standard.preference(
            AppPreferenceKey.enableLockScreenHUD,
            default: PreferenceDefault.enableLockScreenHUD
        )
    }
    
    private init() {
        // Observers are NOT started here — call enable() after checking user preferences.
        // This avoids the historical issue of lock screen features activating unconditionally.
    }
    
    // MARK: - Public API
    
    /// Start observing lock/unlock events. Called from DroppyApp when the preference is enabled.
    func enable() {
        guard !isEnabled else { return }
        isEnabled = true
        setupObservers()
        print("LockScreenManager: ✅ Observers enabled")
    }
    
    /// Stop observing lock/unlock events.
    func disable() {
        guard isEnabled else { return }
        isEnabled = false
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        LockScreenHUDWindowManager.shared.hideAndDestroy()
        isDedicatedHUDActive = false
        transitionPhase = .unlocked
        LockScreenDisplayContextProvider.shared.endLockSession()
        HUDManager.shared.dismiss()
        print("LockScreenManager: ⏹ Observers disabled")
    }
    
    // MARK: - Observer Setup
    
    private func setupObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        
        // Screen sleep = lock (lid closed or manual sleep)
        workspaceCenter.addObserver(
            self,
            selector: #selector(handleScreenSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        
        // Screen wake = unlock (lid opened or manual wake)
        workspaceCenter.addObserver(
            self,
            selector: #selector(handleScreenWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        
        // Session resign = screen locked (power button, hot corner, etc.)
        workspaceCenter.addObserver(
            self,
            selector: #selector(handleScreenSleep),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        
        // Session become active = screen unlocked (after login) - ACTUAL unlock
        workspaceCenter.addObserver(
            self,
            selector: #selector(handleActualUnlock),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
        
        // Also listen to distributed notifications for screen lock (power button)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleScreenSleep),
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )
        
        // Actual unlock notification - ACTUAL unlock
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleActualUnlock),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )
    }
    
    // MARK: - Event Handlers
    
    @objc private func handleScreenSleep() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            
            // Only update state if transitioning from unlocked
            if self.isUnlocked {
                self.transitionPhase = .locking
                _ = LockScreenDisplayContextProvider.shared.beginLockSession()
                self.isUnlocked = false
                self.lastEvent = .locked
                self.lastChangeAt = Date()

                if self.isLockScreenHUDEnabled {
                    // Show dedicated lock screen window (SkyLight-delegated, separate from main notch).
                    self.isDedicatedHUDActive = LockScreenHUDWindowManager.shared.showOnLockScreen()

                    // Gate all other HUDs during lock transition to guarantee no overlap.
                    HUDManager.shared.show(.lockScreen, on: self.preferredLockHUDDisplayID(), duration: 3600)

                    // Keep a single lock HUD animation timeline across lock/unlock events.
                    LockScreenHUDAnimator.shared.transition(to: .locked)
                } else {
                    self.isDedicatedHUDActive = false
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + TransitionTiming.lockExpand) { [weak self] in
                    guard let self else { return }
                    guard !self.isUnlocked else { return }
                    if self.transitionPhase == .locking {
                        self.transitionPhase = .locked
                    }
                }
            }
        }
    }
    
    @objc private func handleScreenWake() {
        // Screen wake can happen on lock screen (just screen brightening)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !self.isUnlocked {
                if self.transitionPhase == .unlocked {
                    self.transitionPhase = .locking
                }
                _ = LockScreenDisplayContextProvider.shared.beginLockSession()
                if self.isLockScreenHUDEnabled {
                    self.isDedicatedHUDActive = LockScreenHUDWindowManager.shared.showOnLockScreen()
                    HUDManager.shared.show(.lockScreen, on: self.preferredLockHUDDisplayID(), duration: 3600)
                } else {
                    self.isDedicatedHUDActive = false
                }
                self.transitionPhase = .locked
            }
        }
    }
    
    /// Called when user actually unlocks (not just screen wake)
    @objc private func handleActualUnlock() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            
            let shouldShowLockHUD = self.isLockScreenHUDEnabled

            // 1. Update state and animate on the SAME lock HUD surface
            if !self.isUnlocked {
                self.transitionPhase = .unlockingHandoff
                self.isUnlocked = true
                self.lastEvent = .unlocked
                self.lastChangeAt = Date()

                if shouldShowLockHUD {
                    // Continue on the same shared animation timeline (no handoff to main notch HUD).
                    LockScreenHUDAnimator.shared.transition(to: .unlocked)
                    HUDManager.shared.show(
                        .lockScreen,
                        on: self.preferredLockHUDDisplayID(),
                        duration: TransitionTiming.unlockCollapse
                    )

                    // Play subtle unlock sound
                    self.playUnlockSound()
                }
            }
            
            guard shouldShowLockHUD else {
                LockScreenHUDWindowManager.shared.hideAndDestroy()
                HUDManager.shared.dismiss()
                self.isDedicatedHUDActive = false
                self.transitionPhase = .unlocked
                LockScreenDisplayContextProvider.shared.endLockSession()
                return
            }

            // 3. Keep the dedicated lock HUD as the single visual owner through unlock handoff.
            // Inline notch remains suppressed until teardown completes.
            LockScreenHUDWindowManager.shared.transitionToDesktopAndHide(
                after: 0,
                collapseDuration: TransitionTiming.unlockCollapse,
                onHandoffStart: nil
            ) {
                // 4. Release lock gate after dedicated surface collapse handoff.
                HUDManager.shared.dismiss()
                self.isDedicatedHUDActive = false
                self.transitionPhase = .unlocked
                LockScreenDisplayContextProvider.shared.endLockSession()
            }
        }
    }
    
    /// Plays a premium, subtle unlock sound
    private func playUnlockSound() {
        if let sound = NSSound(named: "Pop") {
            sound.volume = 0.4
            sound.play()
        }
    }

    private func preferredLockHUDDisplayID() -> CGDirectDisplayID? {
        LockScreenHUDWindowManager.shared.preferredDisplayID
            ?? LockScreenDisplayContextProvider.shared.contextSnapshot()?.displayID
            ?? NSScreen.main?.displayID
            ?? NSScreen.screens.first?.displayID
    }
    
    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }
}
