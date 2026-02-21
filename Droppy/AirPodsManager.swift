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

    /// Per-device disconnect notifications so state can be invalidated immediately.
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]

    /// Address currently associated with the visible/active HUD payload.
    private var currentHUDDeviceAddress: String?
    
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
        disconnectNotifications.values.forEach { $0.unregister() }
        disconnectNotifications.removeAll()
        currentHUDDeviceAddress = nil
        dismissHUD()
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
        showHUD(for: testAirPods, address: nil, triggerDisplayEvent: true)
    }
    
    /// Dismiss the HUD immediately
    func dismissHUD() {
        DispatchQueue.main.async {
            self.isHUDVisible = false
            self.connectedAirPods = nil
            self.currentHUDDeviceAddress = nil
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
                    registerDisconnectNotification(for: device, address: address)
                }
                print("[AirPods] Found already-connected: \(airPods.name) at \(airPods.batteryLevel)%")
            }
        }
    }
    
    // MARK: - Bluetooth Callback
    
    @objc private func handleDeviceConnection(_ notification: IOBluetoothUserNotification?, device: IOBluetoothDevice?) {
        guard let btDevice = device, btDevice.isConnected() else { return }

        let deviceAddress = btDevice.addressString
        if let deviceAddress {
            registerDisconnectNotification(for: btDevice, address: deviceAddress)
        }
        
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
            self?.showHUD(for: audioDevice, address: deviceAddress, triggerDisplayEvent: true)
            self?.scheduleBatteryRefresh(for: btDevice, address: deviceAddress)
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    @objc private func handleDeviceDisconnection(_ notification: IOBluetoothUserNotification?, device: IOBluetoothDevice?) {
        guard let btDevice = device else { return }
        let address = btDevice.addressString

        if let address {
            shownDeviceAddresses.remove(address)
            disconnectNotifications[address]?.unregister()
            disconnectNotifications.removeValue(forKey: address)
        }

        DispatchQueue.main.async {
            if self.currentHUDDeviceAddress == address || self.connectedAirPods?.name == btDevice.name {
                self.connectedAirPods = nil
                self.isHUDVisible = false
                self.currentHUDDeviceAddress = nil
            }
        }

        print("[Audio] Device disconnected: \(btDevice.name ?? "Unknown")")
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
        else if name.contains("beats") || name.contains("powerbeats") || name.contains("studio buds") {
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
    
    private func normalizedBatteryPercent(from rawValue: Any?) -> Int? {
        switch rawValue {
        case let value as Int:
            return (0...100).contains(value) ? value : nil
        case let value as NSNumber:
            let intValue = value.intValue
            return (0...100).contains(intValue) ? intValue : nil
        case let value as String:
            guard let intValue = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
            return (0...100).contains(intValue) ? intValue : nil
        default:
            return nil
        }
    }

    private func readBatteryPercent(from device: IOBluetoothDevice, key: String) -> Int? {
        guard device.responds(to: Selector((key))) else { return nil }
        return normalizedBatteryPercent(from: device.value(forKey: key))
    }

    /// Extract battery levels using IOBluetoothDevice's private selectors
    /// These are undocumented but used by apps like AirBuddy
    private func getBatteryLevels(from device: IOBluetoothDevice, type: ConnectedAirPods.DeviceType) -> (combined: Int, left: Int?, right: Int?, case: Int?) {
        let leftBattery = readBatteryPercent(from: device, key: "batteryPercentLeft")
        let rightBattery = readBatteryPercent(from: device, key: "batteryPercentRight")
        let caseBattery = readBatteryPercent(from: device, key: "batteryPercentCase")
        let singleBattery =
            readBatteryPercent(from: device, key: "batteryPercentSingle") ??
            readBatteryPercent(from: device, key: "batteryPercent") ??
            readBatteryPercent(from: device, key: "batteryPercentMain") ??
            readBatteryPercent(from: device, key: "batteryPercentCombined")
        
        // Calculate combined battery display value
        let combined: Int
        if type == .airpodsMax || type == .headphones {
            // AirPods Max and over-ear headphones use single battery
            if let single = singleBattery {
                combined = single
            } else if let left = leftBattery, let right = rightBattery {
                combined = (left + right) / 2
            } else if let left = leftBattery {
                combined = left
            } else if let right = rightBattery {
                combined = right
            } else if let caseBattery {
                combined = caseBattery
            } else {
                combined = 100
            }
        } else if let left = leftBattery, let right = rightBattery {
            // Average of left and right for regular AirPods
            combined = (left + right) / 2
        } else if let single = singleBattery {
            combined = single
        } else if let left = leftBattery {
            combined = left
        } else if let right = rightBattery {
            combined = right
        } else if let caseBattery {
            combined = caseBattery
        } else {
            // Fallback: no battery info available
            combined = 100
        }
        
        return (combined, leftBattery, rightBattery, caseBattery)
    }
    
    // MARK: - HUD Display
    
    private func showHUD(for airPods: ConnectedAirPods, address: String?, triggerDisplayEvent: Bool) {
        DispatchQueue.main.async {
            self.connectedAirPods = airPods
            self.currentHUDDeviceAddress = address
            if triggerDisplayEvent {
                self.lastConnectionAt = Date()
                self.isHUDVisible = true
            }
            
            print("[AirPods] Showing HUD for: \(airPods.name) - L:\(airPods.leftBattery ?? -1)% R:\(airPods.rightBattery ?? -1)% Case:\(airPods.caseBattery ?? -1)%")
        }
    }

    private func registerDisconnectNotification(for device: IOBluetoothDevice, address: String) {
        guard disconnectNotifications[address] == nil else { return }
        guard let notification = device.register(
            forDisconnectNotification: self,
            selector: #selector(handleDeviceDisconnection(_:device:))
        ) else {
            return
        }
        disconnectNotifications[address] = notification
    }

    /// Refresh battery values shortly after connection because macOS can initially report stale values.
    private func scheduleBatteryRefresh(for device: IOBluetoothDevice, address: String?) {
        let refreshDelays: [TimeInterval] = [1.0, 2.5]
        for delay in refreshDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.isMonitoring, device.isConnected() else { return }

                // If another device took over the HUD, don't let older refreshes override it.
                if let address, let currentAddress = self.currentHUDDeviceAddress, currentAddress != address {
                    return
                }

                guard let refreshedDevice = self.identifyAirPods(device) else { return }
                self.showHUD(for: refreshedDevice, address: address, triggerDisplayEvent: false)
            }
        }
    }
}
