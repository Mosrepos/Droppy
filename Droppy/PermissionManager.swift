//
//  PermissionManager.swift
//  Droppy
//
//  Centralized permission checking with caching to prevent repeated prompts
//  when macOS TCC is slow to sync permission state
//

import Foundation
import AppKit

/// Centralized permission manager with caching
/// Uses UserDefaults to remember when permissions were granted,
/// preventing false negatives when TCC hasn't synced yet
final class PermissionManager {
    static let shared = PermissionManager()
    
    // MARK: - Cache Keys
    private let accessibilityGrantedKey = "accessibilityGranted"
    private let screenRecordingGrantedKey = "screenRecordingGranted"
    private let inputMonitoringGrantedKey = "inputMonitoringGranted"
    
    private init() {}
    
    // MARK: - Accessibility
    
    /// Check if accessibility permission is granted (with cache fallback)
    var isAccessibilityGranted: Bool {
        let trusted = AXIsProcessTrusted()
        
        // Cache if newly trusted
        if trusted {
            UserDefaults.standard.set(true, forKey: accessibilityGrantedKey)
        }
        
        // Use cache to prevent false negatives
        let hasCachedGrant = UserDefaults.standard.bool(forKey: accessibilityGrantedKey)
        return trusted || hasCachedGrant
    }
    
    /// Request accessibility permission (shows system dialog)
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    
    // MARK: - Screen Recording
    
    /// Check if screen recording permission is granted (with cache fallback)
    var isScreenRecordingGranted: Bool {
        let granted = CGPreflightScreenCaptureAccess()
        
        // Cache if newly granted
        if granted {
            UserDefaults.standard.set(true, forKey: screenRecordingGrantedKey)
        }
        
        // Use cache to prevent false negatives
        let hasCachedGrant = UserDefaults.standard.bool(forKey: screenRecordingGrantedKey)
        return granted || hasCachedGrant
    }
    
    /// Request screen recording permission (shows system dialog)
    /// Returns true if granted (may require app restart)
    @discardableResult
    func requestScreenRecording() -> Bool {
        return CGRequestScreenCaptureAccess()
    }
    
    // MARK: - Input Monitoring
    
    /// Check if input monitoring permission is granted (with cache fallback)
    /// Note: This relies on IOHIDManager success which is tracked by GlobalHotKey
    func isInputMonitoringGranted(runtimeCheck: Bool) -> Bool {
        let hasCachedGrant = UserDefaults.standard.bool(forKey: inputMonitoringGrantedKey)
        return runtimeCheck || hasCachedGrant
    }
    
    /// Mark input monitoring as granted (called by GlobalHotKey on success)
    func markInputMonitoringGranted() {
        UserDefaults.standard.set(true, forKey: inputMonitoringGrantedKey)
    }
    
    // MARK: - Settings URLs
    
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}
