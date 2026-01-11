//
//  AirPodsManager.swift
//  Droppy
//
//  Created by Droppy on 11/01/2026.
//  Manages AirPods Bluetooth detection and HUD triggering
//
//  Uses IOBluetooth for connection detection and battery level extraction.
//  Battery levels are obtained via private API selectors (batteryPercentLeft, etc.)
//  Requires NSBluetoothAlwaysUsageDescription in Info.plist.
//

import Foundation
import IOBluetooth

/// Manages AirPods connection detection and HUD display
@Observable
final class AirPodsManager {
    
    // MARK: - Singleton
    
    static let shared = AirPodsManager()
    
    // MARK: - Published State
    
    /// Whether the AirPods HUD should be visible
    var isHUDVisible = false
    
    /// Currently connected AirPods (nil when not connected or HUD dismissed)
    var connectedAirPods: ConnectedAirPods?
    
    /// Timestamp of last connection event (for triggering HUD)
    var lastConnectionAt = Date.distantPast
    
    /// Duration to show the HUD
    let visibleDuration: TimeInterval = 4.0
    
    // MARK: - Private State
    
    /// IOBluetooth notification reference - MUST be retained or callbacks fail
    private var connectionNotification: IOBluetoothUserNotification?
    
    /// Whether monitoring is active
    private var isMonitoring = false
    
    /// Debounce timer to prevent rapid reconnection spam
    private var debounceWorkItem: DispatchWorkItem?
    
    /// Track devices we've already shown HUD for (to avoid re-triggering on same connection)
    private var shownDeviceAddresses: Set<String> = []
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public API
    
    /// Start monitoring for AirPods connections
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        print("[AirPods] Starting connection monitoring")
        
        // Register for Bluetooth device connections
        connectionNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(handleDeviceConnection(_:device:))
        )
        
        isMonitoring = true
        
        // Check for already-connected AirPods
        checkExistingConnections()
    }
    
    /// Stop monitoring for AirPods connections
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        print("[AirPods] Stopping connection monitoring")
        
        // Unregister notifications
        connectionNotification?.unregister()
        connectionNotification = nil
        
        debounceWorkItem?.cancel()
        isMonitoring = false
        shownDeviceAddresses.removeAll()
    }
    
    /// Manually trigger HUD for testing
    func triggerTestHUD() {
        let testAirPods = ConnectedAirPods(
            name: "Test AirPods Pro",
            type: .pro,
            batteryLevel: 85,
            leftBattery: 80,
            rightBattery: 90,
            caseBattery: 75
        )
        showHUD(for: testAirPods)
    }
    
    /// Dismiss the HUD immediately
    func dismissHUD() {
        DispatchQueue.main.async {
            self.isHUDVisible = false
            self.connectedAirPods = nil
        }
    }
    
    // MARK: - Check Existing Connections
    
    private func checkExistingConnections() {
        // Get all paired devices
        guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }
        
        for device in pairedDevices {
            if device.isConnected(), let airPods = identifyAirPods(device) {
                // Don't show HUD for already-connected devices on app launch
                if let address = device.addressString {
                    shownDeviceAddresses.insert(address)
                }
                print("[AirPods] Found already-connected: \(airPods.name) at \(airPods.batteryLevel)%")
            }
        }
    }
    
    // MARK: - Bluetooth Callback
    
    @objc private func handleDeviceConnection(_ notification: IOBluetoothUserNotification?, device: IOBluetoothDevice?) {
        guard let device = device, device.isConnected() else { return }
        
        // Check if this is an AirPods device
        guard let airPods = identifyAirPods(device) else {
            print("[AirPods] Device connected but not AirPods: \(device.name ?? "Unknown")")
            return
        }
        
        // Check if we've already shown HUD for this device (avoid duplicate triggers)
        if let address = device.addressString {
            if shownDeviceAddresses.contains(address) {
                print("[AirPods] Already shown HUD for: \(airPods.name), skipping")
                return
            }
            shownDeviceAddresses.insert(address)
            
            // Clear this device after some time so next connection triggers HUD
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                self?.shownDeviceAddresses.remove(address)
            }
        }
        
        print("[AirPods] Detected connection: \(airPods.name) - Battery: \(airPods.batteryLevel)%")
        
        // Debounce rapid reconnections (AirPods can connect/disconnect in quick succession)
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.showHUD(for: airPods)
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }
    
    // MARK: - AirPods Identification
    
    private func identifyAirPods(_ device: IOBluetoothDevice) -> ConnectedAirPods? {
        guard let name = device.name?.lowercased() else { return nil }
        
        // Check if device name contains AirPods indicators
        guard name.contains("airpods") else { return nil }
        
        // Determine type based on name
        let type: ConnectedAirPods.AirPodsType
        if name.contains("max") {
            type = .max
        } else if name.contains("pro") {
            type = .pro
        } else if name.contains("3") || name.contains("gen 3") || name.contains("third") {
            type = .gen3
        } else {
            type = .standard
        }
        
        // Get battery levels using private API
        let batteryInfo = getBatteryLevels(from: device, type: type)
        
        return ConnectedAirPods(
            name: device.name ?? "AirPods",
            type: type,
            batteryLevel: batteryInfo.combined,
            leftBattery: batteryInfo.left,
            rightBattery: batteryInfo.right,
            caseBattery: batteryInfo.case
        )
    }
    
    // MARK: - Battery Level Extraction (Private API)
    
    /// Extract battery levels using IOBluetoothDevice's private selectors
    /// These are undocumented but used by apps like AirBuddy
    private func getBatteryLevels(from device: IOBluetoothDevice, type: ConnectedAirPods.AirPodsType) -> (combined: Int, left: Int?, right: Int?, case: Int?) {
        var leftBattery: Int?
        var rightBattery: Int?
        var caseBattery: Int?
        var singleBattery: Int?
        
        // Try to get individual battery levels using private selectors
        // These selectors exist in IOBluetoothDevice but are not publicly documented
        
        // Left earbud battery
        if device.responds(to: Selector(("batteryPercentLeft"))) {
            if let value = device.value(forKey: "batteryPercentLeft") as? Int, value >= 0, value <= 100 {
                leftBattery = value
            }
        }
        
        // Right earbud battery
        if device.responds(to: Selector(("batteryPercentRight"))) {
            if let value = device.value(forKey: "batteryPercentRight") as? Int, value >= 0, value <= 100 {
                rightBattery = value
            }
        }
        
        // Case battery
        if device.responds(to: Selector(("batteryPercentCase"))) {
            if let value = device.value(forKey: "batteryPercentCase") as? Int, value >= 0, value <= 100 {
                caseBattery = value
            }
        }
        
        // Single battery (for AirPods Max or when left/right not available)
        if device.responds(to: Selector(("batteryPercentSingle"))) {
            if let value = device.value(forKey: "batteryPercentSingle") as? Int, value >= 0, value <= 100 {
                singleBattery = value
            }
        }
        
        // Calculate combined battery display value
        let combined: Int
        if type == .max {
            // AirPods Max uses single battery
            combined = singleBattery ?? 100
        } else if let left = leftBattery, let right = rightBattery {
            // Average of left and right for regular AirPods
            combined = (left + right) / 2
        } else if let single = singleBattery {
            combined = single
        } else if let left = leftBattery {
            combined = left
        } else if let right = rightBattery {
            combined = right
        } else {
            // Fallback: no battery info available
            combined = 100
        }
        
        return (combined, leftBattery, rightBattery, caseBattery)
    }
    
    // MARK: - HUD Display
    
    private func showHUD(for airPods: ConnectedAirPods) {
        DispatchQueue.main.async {
            self.connectedAirPods = airPods
            self.lastConnectionAt = Date()
            self.isHUDVisible = true
            
            print("[AirPods] Showing HUD for: \(airPods.name) - L:\(airPods.leftBattery ?? -1)% R:\(airPods.rightBattery ?? -1)% Case:\(airPods.caseBattery ?? -1)%")
        }
    }
}
