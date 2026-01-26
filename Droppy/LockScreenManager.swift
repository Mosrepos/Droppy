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

/// Manages screen lock/unlock detection for HUD display
/// Uses NSWorkspace notifications to detect when screens sleep/wake
class LockScreenManager: ObservableObject {
    static let shared = LockScreenManager()
    
    /// Current state: true = unlocked (awake), false = locked (asleep)
    @Published private(set) var isUnlocked: Bool = true
    
    /// Timestamp of last state change (triggers HUD)
    @Published private(set) var lastChangeAt: Date = .distantPast
    
    /// The event that triggered the last change
    @Published private(set) var lastEvent: LockEvent = .none
    
    /// Duration the HUD should stay visible
    let visibleDuration: TimeInterval = 2.5
    
    /// Lock event types
    enum LockEvent {
        case none
        case locked    // Screen went to sleep / lid closed
        case unlocked  // Screen woke up / lid opened
    }
    
    private init() {
        setupObservers()
    }
    
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
        
        // Session become active = screen unlocked (after login)
        workspaceCenter.addObserver(
            self,
            selector: #selector(handleScreenWake),
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
        
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleScreenWake),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )
    }
    
    @objc private func handleScreenSleep() {
        // Update internal state IMMEDIATELY - the notch is visible on lock screen via SkyLight
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Always show the panel when screen locks/dims (even if already locked)
            // This handles: initial lock, screen dim, and re-lock after partial wake
            LockScreenMediaPanelManager.shared.showPanel()
            
            // Only update state if transitioning from unlocked
            if self.isUnlocked {
                self.isUnlocked = false
                self.lastEvent = .locked
                self.lastChangeAt = Date()
            }
        }
    }
    
    @objc private func handleScreenWake() {
        // Hide lock screen media panel (user is unlocking)
        LockScreenMediaPanelManager.shared.hidePanel()
        
        // Trigger unlock HUD IMMEDIATELY - the notch is visible on lock screen via SkyLight
        // The user will see the unlock animation on the lock screen before it transitions
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Prevent duplicate triggers
            guard !self.isUnlocked else { return }
            self.isUnlocked = true
            self.lastEvent = .unlocked
            self.lastChangeAt = Date()
        }
    }
    
    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }
}
