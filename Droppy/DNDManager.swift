//
//  DNDManager.swift
//  Droppy
//
//  Created by Droppy on 17/01/2026.
//  Monitors Do Not Disturb / Focus Mode state
//

import Foundation
import Combine

/// Manages DND/Focus state monitoring for HUD display
/// Uses DistributedNotificationCenter for Focus state changes
final class DNDManager: ObservableObject {
    static let shared = DNDManager()
    
    // MARK: - Published Properties
    @Published private(set) var isDNDActive: Bool = false
    @Published private(set) var lastChangeAt: Date = .distantPast
    
    /// Duration to show the HUD (seconds)
    let visibleDuration: TimeInterval = 2.0
    
    // MARK: - Private State
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var hasInitialized = false
    
    // Focus mode file path (requires Full Disk Access)
    private let dndPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
    
    // MARK: - Initialization
    private init() {
        // Read initial state without triggering HUD
        checkDNDState(triggerHUD: false)
        hasInitialized = true
        
        // Start monitoring
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Monitoring
    
    private func startMonitoring() {
        // Method 1: Watch the Assertions.json file (most reliable but needs Full Disk Access)
        startFileMonitoring()
        
        // Method 2: Listen for distributed notifications (works without special permissions)
        // These notifications are posted when Focus mode changes
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleFocusChange),
            name: NSNotification.Name("com.apple.donotdisturb.statechanged"),
            object: nil
        )
        
        // Alternative notification names that may be used
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleFocusChange),
            name: NSNotification.Name("com.apple.dnd.statechanged"),
            object: nil
        )
        
        print("DNDManager: Started monitoring Focus state")
    }
    
    private func startFileMonitoring() {
        // Ensure file exists and is readable
        guard FileManager.default.fileExists(atPath: dndPath.path),
              FileManager.default.isReadableFile(atPath: dndPath.path) else {
            print("DNDManager: Cannot access Assertions.json (need Full Disk Access)")
            return
        }
        
        // Open file descriptor
        fileDescriptor = open(dndPath.path, O_EVTONLY)
        guard fileDescriptor != -1 else {
            print("DNDManager: Failed to open file descriptor")
            return
        }
        
        // Create dispatch source to watch for writes
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: .global(qos: .background)
        )
        
        source?.setEventHandler { [weak self] in
            self?.checkDNDState(triggerHUD: true)
        }
        
        source?.setCancelHandler { [weak self] in
            guard let self = self else { return }
            if self.fileDescriptor != -1 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }
        
        source?.resume()
        print("DNDManager: File monitoring active at \(dndPath.path)")
    }
    
    private func stopMonitoring() {
        source?.cancel()
        source = nil
        DistributedNotificationCenter.default().removeObserver(self)
    }
    
    @objc private func handleFocusChange(_ notification: Notification) {
        // Debounce rapid notifications
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.checkDNDState(triggerHUD: true)
        }
    }
    
    private func checkDNDState(triggerHUD: Bool) {
        var newState = false
        
        // Try to read from file first (most accurate)
        if FileManager.default.isReadableFile(atPath: dndPath.path),
           let data = try? Data(contentsOf: dndPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let dataArray = json["data"] as? [[String: Any]],
           let firstItem = dataArray.first,
           let assertions = firstItem["storeAssertionRecords"] as? [Any] {
            // If storeAssertionRecords is not empty, Focus is active
            newState = !assertions.isEmpty
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if self.isDNDActive != newState {
                self.isDNDActive = newState
                
                if self.hasInitialized && triggerHUD {
                    self.lastChangeAt = Date()
                    print("DNDManager: Focus is now \(newState ? "ON" : "OFF")")
                }
            }
        }
    }
}
