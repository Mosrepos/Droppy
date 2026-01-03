//
//  DroppyApp.swift
//  Droppy
//
//  Created by Jordy Spruit on 02/01/2026.
//

import SwiftUI

/// Main application entry point for Droppy
@main
struct DroppyApp: App {
    /// App delegate for handling app lifecycle and notch window setup
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @AppStorage("showInMenuBar") private var showInMenuBar = true
    
    init() {
        // Set as accessory app (no dock icon) early, but after SwiftUI initializes
        // This ensures MenuBarExtra is registered before hiding from dock
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }
    
    var body: some Scene {
        Settings {
            if #available(macOS 15.0, *) {
                SettingsView()
                    .containerBackground(.clear, for: .window)
            } else {
                SettingsView()
            }
        }
        
        MenuBarExtra("Droppy", systemImage: "tray.and.arrow.down.fill", isInserted: $showInMenuBar) {
            Button("Check for Updates...") {
                UpdateChecker.shared.checkAndNotify()
            }
            
            Divider()
            
            Button("Settings...") {
                SettingsWindowController.shared.showSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
            
            Divider()
            
            Button("Quit Droppy") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}

/// App delegate to manage application lifecycle and notch window
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start monitoring for drag events
        DragMonitor.shared.startMonitoring()
        
        // Setup the notch overlay window
        NotchWindowController.shared.setupNotchWindow()
        
        // Initialize floating basket controller (observes jiggle detection)
        _ = FloatingBasketWindowController.shared
        
        // Check for updates in background (notify only if update available)
        Task {
            await UpdateChecker.shared.checkForUpdates()
            if UpdateChecker.shared.updateAvailable {
                UpdateChecker.shared.showUpdateAlert()
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Stop drag monitoring
        DragMonitor.shared.stopMonitoring()
        
        // Close notch window
        NotchWindowController.shared.closeWindow()
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    // Prevent app from closing when the settings window is closed
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
