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
/// Uses file monitoring of ~/Library/DoNotDisturb/DB/Assertions.json
/// Requires Full Disk Access permission
final class DNDManager: ObservableObject {
    static let shared = DNDManager()
    
    // MARK: - Published Properties
    @Published private(set) var isDNDActive: Bool = false
    @Published private(set) var lastChangeAt: Date = .distantPast
    @Published private(set) var hasAccess: Bool = false
    
    /// Duration to show the HUD (seconds)
    let visibleDuration: TimeInterval = 2.0
    
    // MARK: - Private State
    private var pollingSource: DispatchSourceTimer?
    private var hasInitialized = false
    
    // Focus mode file path (requires Full Disk Access)
    private let dndPath: String
    
    // MARK: - Initialization
    private init() {
        dndPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json").path
        
        // Initial check
        let (access, state) = readDNDState()
        hasAccess = access
        isDNDActive = state
        
        if access {
            print("DNDManager: ✅ Full Disk Access granted, isDND: \(state)")
            hasInitialized = true
            startPolling()
        } else {
            print("DNDManager: ❌ No Full Disk Access")
        }
    }
    
    deinit {
        pollingSource?.cancel()
    }
    
    // MARK: - Public API
    
    func recheckAccess() {
        let (access, _) = readDNDState()
        hasAccess = access
        if access && pollingSource == nil {
            hasInitialized = true
            startPolling()
        }
    }
    
    // MARK: - Polling
    
    private func startPolling() {
        pollingSource?.cancel()
        
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
        timer.setEventHandler { [weak self] in
            self?.checkDNDState()
        }
        timer.resume()
        pollingSource = timer
        print("DNDManager: Polling started")
    }
    
    // MARK: - State Reading
    
    private func readDNDState() -> (hasAccess: Bool, isDND: Bool) {
        guard let fileHandle = FileHandle(forReadingAtPath: dndPath) else {
            return (false, false)
        }
        defer { try? fileHandle.close() }
        
        let data = fileHandle.readDataToEndOfFile()
        guard !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]],
              let firstItem = dataArray.first,
              let assertions = firstItem["storeAssertionRecords"] as? [Any] else {
            return (true, false) // Has access but couldn't parse (might be empty/transitioning)
        }
        
        return (true, !assertions.isEmpty)
    }
    
    private func checkDNDState() {
        let (_, newState) = readDNDState()
        
        if isDNDActive != newState {
            isDNDActive = newState
            if hasInitialized {
                lastChangeAt = Date()
                print("DNDManager: Focus changed to \(newState ? "ON" : "OFF")")
            }
        }
    }
}
