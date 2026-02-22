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
            type: .airpodsPro,
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
        guard let btDevice = device, btDevice.isConnected() else { return }
        
        // Check if this is a Bluetooth audio device
        guard let audioDevice = identifyAirPods(btDevice) else {
            print("[Audio] Device connected but not audio: \(btDevice.name ?? "Unknown")")
            return
        }
        
        // Check if we've already shown HUD for this device (avoid duplicate triggers)
        if let address = btDevice.addressString {
            if shownDeviceAddresses.contains(address) {
                print("[Audio] Already shown HUD for: \(audioDevice.name), skipping")
                return
            }
            shownDeviceAddresses.insert(address)
            
            // Clear this device after some time so next connection triggers HUD
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                self?.shownDeviceAddresses.remove(address)
            }
        }
        
        print("[Audio] Detected connection: \(audioDevice.name) (\(audioDevice.type.displayName)) - Battery: \(audioDevice.batteryLevel)%")
        
        // Debounce rapid reconnections (devices can connect/disconnect in quick succession)
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.showHUD(for: audioDevice)
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }
    
    // MARK: - Device Identification (AirPods + Generic Headphones)
    
    /// Identify Bluetooth audio device and determine its type
    private func identifyAirPods(_ device: IOBluetoothDevice) -> ConnectedAirPods? {
        guard let name = device.name?.lowercased() else { return nil }
        
        // Determine device type based on name
        let type: ConnectedAirPods.DeviceType
        
        // === AirPods Family ===
        if name.contains("airpods") {
            if name.contains("max") {
                type = .airpodsMax
            } else if name.contains("pro") {
                type = .airpodsPro
            } else if name.contains("3") || name.contains("gen 3") || name.contains("third") {
                type = .airpodsGen3
            } else {
                type = .airpods
            }
        }
        // === Beats Products ===
        else if isLikelyBeatsDevice(name) {
            type = .beats
        }
        // === Generic Earbuds (wireless earbuds from various brands) ===
        else if name.contains("buds") || name.contains("earbuds") || name.contains("earbud") ||
                name.contains("galaxy buds") || name.contains("pixel buds") || 
                name.contains("jabra") || name.contains("wf-") { // Sony WF- series
            type = .earbuds
        }
        // === Generic Headphones (over-ear/on-ear) ===
        else if name.contains("headphone") || name.contains("wh-") || // Sony WH- series
                name.contains("bose") || name.contains("quietcomfort") ||
                name.contains("sennheiser") || name.contains("momentum") ||
                name.contains("jbl") || name.contains("skullcandy") ||
                name.contains("audio-technica") || name.contains("anker") ||
                name.contains("soundcore") {
            type = .headphones
        }
        // === Not a recognized audio device ===
        else {
            // Check device class for audio devices
            let deviceClass = device.classOfDevice
            let majorClass = (deviceClass >> 8) & 0x1F
            let isAudioDevice = majorClass == 0x04 // Audio/Video device class
            
            if isAudioDevice {
                // It's an audio device but we don't recognize the brand - use generic headphones
                type = .headphones
            } else {
                // Not an audio device
                return nil
            }
        }
        
        // Get battery levels using private API
        let batteryInfo = getBatteryLevels(from: device, type: type)
        
        return ConnectedAirPods(
            name: device.name ?? "Headphones",
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
    private func getBatteryLevels(from device: IOBluetoothDevice, type: ConnectedAirPods.DeviceType) -> (combined: Int, left: Int?, right: Int?, case: Int?) {
        var leftBattery: Int?
        var rightBattery: Int?
        var caseBattery: Int?
        var singleBattery: Int?
        var combinedBattery: Int?
        
        func normalizedBatteryValue(_ rawValue: Any?, depth: Int = 0) -> Int? {
            guard depth <= 4 else { return nil }
            
            func validatedBatteryValue(_ value: Int) -> Int? {
                (0...100).contains(value) ? value : nil
            }
            
            func normalizedBatteryValueFromDictionary(_ dictionary: [String: Any], depth: Int) -> Int? {
                let valueKeys = [
                    "value",
                    "level",
                    "percent",
                    "batteryLevel",
                    "batteryPercent",
                    "Value",
                    "Level",
                    "Percent",
                    "BatteryPercent"
                ]
                let nestedPayloadKeys = ["payload", "data", "value"]
                
                for key in valueKeys {
                    guard let entry = dictionary[key] else { continue }
                    if let resolved = normalizedBatteryValue(entry, depth: depth + 1) {
                        return resolved
                    }
                }
                
                for key in nestedPayloadKeys {
                    guard let entry = dictionary[key] else { continue }
                    if let resolved = normalizedBatteryValue(entry, depth: depth + 1) {
                        return resolved
                    }
                }
                
                return nil
            }
            
            switch rawValue {
            case let value as Int:
                return validatedBatteryValue(value)
            case let value as UInt8:
                let resolved = Int(value)
                return validatedBatteryValue(resolved)
            case let value as Int64:
                let resolved = Int(value)
                return validatedBatteryValue(resolved)
            case let value as NSNumber:
                let resolved = value.intValue
                return validatedBatteryValue(resolved)
            case let value as [String: Any]:
                return normalizedBatteryValueFromDictionary(value, depth: depth)
            case let value as NSDictionary:
                var dictionary: [String: Any] = [:]
                for (key, entry) in value {
                    guard let stringKey = key as? String else { continue }
                    dictionary[stringKey] = entry
                }
                return normalizedBatteryValueFromDictionary(dictionary, depth: depth)
            default:
                return nil
            }
        }
        
        func readBatteryValue(for selectorName: String) -> (raw: Any?, normalized: Int?)? {
            guard device.responds(to: Selector((selectorName))) else { return nil }
            let rawValue = device.value(forKey: selectorName)
            return (rawValue, normalizedBatteryValue(rawValue))
        }
        
        // Try to get individual battery levels using private selectors
        // These selectors exist in IOBluetoothDevice but are not publicly documented
        
        // Left earbud battery
        let leftRead = readBatteryValue(for: "batteryPercentLeft")
        leftBattery = leftRead?.normalized
        
        // Right earbud battery
        let rightRead = readBatteryValue(for: "batteryPercentRight")
        rightBattery = rightRead?.normalized
        
        // Case battery
        let caseRead = readBatteryValue(for: "batteryPercentCase")
        caseBattery = caseRead?.normalized
        
        // Single battery (for AirPods Max or when left/right not available)
        let singleRead = readBatteryValue(for: "batteryPercentSingle")
        singleBattery = singleRead?.normalized
        
        // Combined battery is common on single-cell headphones (including some Beats models).
        let combinedRead = readBatteryValue(for: "batteryPercentCombined")
        combinedBattery = combinedRead?.normalized
        
        // Legacy headset path still used by some Bluetooth devices.
        let headsetRead = readBatteryValue(for: "headsetBattery")
        let headsetBattery = headsetRead?.normalized
        
        if type == .beats,
           leftBattery == nil,
           rightBattery == nil,
           caseBattery == nil,
           singleBattery == nil,
           combinedBattery == nil,
           headsetBattery == nil {
            let rawDebugValues: [String: Any?] = [
                "batteryPercentLeft": leftRead?.raw,
                "batteryPercentRight": rightRead?.raw,
                "batteryPercentCase": caseRead?.raw,
                "batteryPercentSingle": singleRead?.raw,
                "batteryPercentCombined": combinedRead?.raw,
                "headsetBattery": headsetRead?.raw
            ]
            print("[AirPods][Beats] Battery extraction returned nil for all selectors. Raw selector values: \(rawDebugValues)")
        }
        
        // Calculate combined battery display value
        let combined: Int
        if let left = leftBattery, let right = rightBattery {
            // Stereo earbuds/headsets: use average when both channels are present.
            combined = (left + right) / 2
        } else if type == .airpodsMax || type == .headphones || type == .beats {
            // AirPods Max and over-ear headphones use single battery
            combined = singleBattery
                ?? combinedBattery
                ?? headsetBattery
                ?? leftBattery
                ?? rightBattery
                ?? 100
        } else if let combinedValue = combinedBattery {
            combined = combinedValue
        } else if let single = singleBattery {
            combined = single
        } else if let headset = headsetBattery {
            combined = headset
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
    
    private func isLikelyBeatsDevice(_ deviceName: String) -> Bool {
        let beatsModelTokens = [
            "beats",
            "powerbeats",
            "studio buds",
            "studio buds+",
            "fit pro",
            "solo buds",
            "solo3",
            "solo 3",
            "solo4",
            "solo 4",
            "solo pro",
            "studio3",
            "studio 3",
            "studio3 wireless",
            "studio pro",
            "beatsx",
            "beats x",
            "urbeats"
        ]
        
        return beatsModelTokens.contains { deviceName.contains($0) }
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
