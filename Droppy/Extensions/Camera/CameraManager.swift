//
//  CameraManager.swift
//  Droppy
//
//  Manages camera capture session lifecycle for Notchface shelf previews.
//

import SwiftUI
import Combine
@preconcurrency import AVFoundation

nonisolated final class CameraSessionBox: @unchecked Sendable {
    let session = AVCaptureSession()
}

struct CameraSelectionOption: Identifiable, Equatable {
    let id: String
    let displayName: String
    let icon: String
}

@MainActor
final class CameraManager: ObservableObject {
    static let shared = CameraManager()
    nonisolated let objectWillChange = ObservableObjectPublisher()

    @Published var isRunning: Bool = false
    @Published var permissionStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published var videoAspectRatio: CGFloat = 16.0 / 9.0
    @Published private(set) var availableCameraDevices: [CameraSelectionOption] = []

    @AppStorage(AppPreferenceKey.cameraInstalled) var isInstalled: Bool = PreferenceDefault.cameraInstalled
    @AppStorage(AppPreferenceKey.cameraEnabled) var isEnabled: Bool = PreferenceDefault.cameraEnabled

    nonisolated let sessionBox = CameraSessionBox()
    nonisolated let sessionQueue = DispatchQueue(label: "com.droppy.camera.session")

    nonisolated var session: AVCaptureSession {
        sessionBox.session
    }

    private var isConfigured = false
    private var isStarting = false
    private var activePreviewCount = 0
    private var activeDeviceUniqueID: String?
    private var cameraDeviceObservers: [NSObjectProtocol] = []

    private init() {
        refreshAvailableDevices()
        observeCameraDeviceChanges()
    }

    // MARK: - Public API

    func previewDidAppear() {
        activePreviewCount += 1
        startSessionIfNeeded()
    }

    func previewDidDisappear() {
        activePreviewCount = max(0, activePreviewCount - 1)
        if activePreviewCount == 0 {
            stopSession()
        }
    }

    func requestAccess() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        permissionStatus = status

        if status == .authorized {
            startSessionIfNeeded()
            return
        }

        guard status == .notDetermined else { return }

        AVCaptureDevice.requestAccess(for: .video) { granted in
            Task { @MainActor in
                let manager = CameraManager.shared
                manager.permissionStatus = granted ? .authorized : .denied
                if granted {
                    manager.startSessionIfNeeded()
                }
            }
        }
    }

    func cleanup() {
        isInstalled = false
        isEnabled = PreferenceDefault.cameraEnabled
        activePreviewCount = 0
        isConfigured = false
        isStarting = false
        activeDeviceUniqueID = nil
        stopSession()
        resetSession()
    }

    func refreshAvailableDevices() {
        availableCameraDevices = discoveredConnectedDevices().map { device in
            CameraSelectionOption(
                id: device.uniqueID,
                displayName: device.localizedName,
                icon: iconName(for: device)
            )
        }
    }

    func setPreferredDeviceID(_ deviceID: String?) {
        let normalized = normalizedDeviceID(deviceID)

        if let normalized {
            UserDefaults.standard.set(normalized, forKey: AppPreferenceKey.cameraPreferredDeviceID)
        } else {
            UserDefaults.standard.removeObject(forKey: AppPreferenceKey.cameraPreferredDeviceID)
        }

        refreshAvailableDevices()

        let needsReconfigure = shouldReconfigureForPreferredDevice()
        if needsReconfigure {
            resetSessionConfiguration()
        }
        if activePreviewCount > 0 && (!isConfigured || needsReconfigure) {
            startSessionIfNeeded()
        }
    }

    // MARK: - Internal

    private func startSessionIfNeeded() {
        guard isInstalled && isEnabled else {
            stopSession()
            return
        }

        guard activePreviewCount > 0 else { return }

        let status = AVCaptureDevice.authorizationStatus(for: .video)
        permissionStatus = status

        switch status {
        case .authorized:
            if shouldReconfigureForPreferredDevice() {
                resetSessionConfiguration()
            }
            configureSessionIfNeeded()
            guard isConfigured else {
                stopSession()
                return
            }
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    let manager = CameraManager.shared
                    manager.permissionStatus = granted ? .authorized : .denied
                    if granted {
                        manager.startSessionIfNeeded()
                    }
                }
            }
        case .denied, .restricted:
            stopSession()
        @unknown default:
            stopSession()
        }
    }

    private func configureSessionIfNeeded() {
        guard !isConfigured else { return }

        var aspectRatio: CGFloat?
        var selectedDeviceID: String?
        var didAddInput = false
        let localBox = sessionBox

        sessionQueue.sync {
            let session = localBox.session
            session.beginConfiguration()
            session.sessionPreset = .high

            let device = preferredCameraDevice()

            guard let camera = device else {
                session.commitConfiguration()
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: camera)
                if session.canAddInput(input) {
                    session.addInput(input)
                    selectedDeviceID = camera.uniqueID
                    didAddInput = true
                }

                let format = camera.activeFormat.formatDescription
                let dimensions = CMVideoFormatDescriptionGetDimensions(format)
                if dimensions.height > 0 {
                    aspectRatio = CGFloat(dimensions.width) / CGFloat(dimensions.height)
                }
            } catch {
                session.commitConfiguration()
                return
            }

            session.commitConfiguration()
        }

        if let aspectRatio {
            videoAspectRatio = aspectRatio
        }
        activeDeviceUniqueID = selectedDeviceID

        isConfigured = didAddInput
    }

    private func startSession() {
        if isRunning || isStarting { return }
        isStarting = true

        let localBox = sessionBox
        sessionQueue.async {
            let session = localBox.session
            if !session.isRunning {
                session.startRunning()
            }

            Task { @MainActor in
                let manager = CameraManager.shared
                manager.isRunning = true
                manager.isStarting = false
            }
        }
    }

    private func stopSession() {
        isStarting = false

        let localBox = sessionBox
        sessionQueue.async {
            let session = localBox.session
            if session.isRunning {
                session.stopRunning()
            }

            Task { @MainActor in
                let manager = CameraManager.shared
                manager.isRunning = false
                manager.isStarting = false
            }
        }
    }

    private func resetSession() {
        let localBox = sessionBox
        sessionQueue.async {
            let session = localBox.session
            session.beginConfiguration()
            for input in session.inputs {
                session.removeInput(input)
            }
            for output in session.outputs {
                session.removeOutput(output)
            }
            session.commitConfiguration()
        }
    }

    private func resetSessionConfiguration() {
        isConfigured = false
        activeDeviceUniqueID = nil

        let localBox = sessionBox
        sessionQueue.sync {
            let session = localBox.session
            session.beginConfiguration()
            for input in session.inputs {
                session.removeInput(input)
            }
            session.commitConfiguration()
        }
    }

    private func shouldReconfigureForPreferredDevice() -> Bool {
        guard isConfigured else { return false }
        guard let preferred = preferredCameraDevice() else { return false }
        return preferred.uniqueID != activeDeviceUniqueID
    }

    private func preferredCameraDevice() -> AVCaptureDevice? {
        let devices = discoveredConnectedDevices()

        guard !devices.isEmpty else {
            return AVCaptureDevice.default(for: .video)
        }

        if let preferredDeviceID = preferredDeviceID(),
           let preferred = devices.first(where: { $0.uniqueID == preferredDeviceID }) {
            return preferred
        }

        return devices.first ?? AVCaptureDevice.default(for: .video)
    }

    private func discoveredConnectedDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: availableVideoDeviceTypes(),
            mediaType: .video,
            position: .unspecified
        ).devices
        .filter(\.isConnected)
        .sorted { lhs, rhs in
            let lhsPriority = autoSelectionPriority(for: lhs)
            let rhsPriority = autoSelectionPriority(for: rhs)
            if lhsPriority == rhsPriority {
                return lhs.localizedName.localizedCaseInsensitiveCompare(rhs.localizedName) == .orderedAscending
            }
            return lhsPriority < rhsPriority
        }
    }

    private func autoSelectionPriority(for device: AVCaptureDevice) -> Int {
        // Prefer external/USB cameras first for external-display and clamshell setups.
        if isExternalCamera(device) {
            return 0
        }

        if #available(macOS 13.0, *) {
            if device.deviceType == .continuityCamera {
                return 1
            }
        }

        if device.deviceType == .builtInWideAngleCamera && device.position == .front {
            return 2
        }

        if device.deviceType == .builtInWideAngleCamera {
            return 3
        }

        return 4
    }

    private func availableVideoDeviceTypes() -> [AVCaptureDevice.DeviceType] {
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        if #available(macOS 14.0, *) {
            types.insert(.external, at: 0)
        } else {
            types.insert(AVCaptureDevice.DeviceType(rawValue: "AVCaptureDeviceTypeExternalUnknown"), at: 0)
        }
        if #available(macOS 13.0, *) {
            types.append(.continuityCamera)
        }
        return types
    }

    private func preferredDeviceID() -> String? {
        normalizedDeviceID(UserDefaults.standard.string(forKey: AppPreferenceKey.cameraPreferredDeviceID))
    }

    private func iconName(for device: AVCaptureDevice) -> String {
        if isExternalCamera(device) {
            return "web.camera.fill"
        }
        if #available(macOS 13.0, *), device.deviceType == .continuityCamera {
            return "iphone.gen3.camera"
        }
        if device.position == .front {
            return "camera.fill"
        }
        return "video.fill"
    }

    private func observeCameraDeviceChanges() {
        let center = NotificationCenter.default
        cameraDeviceObservers = [
            center.addObserver(
                forName: .AVCaptureDeviceWasConnected,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    CameraManager.shared.handleDeviceChange()
                }
            },
            center.addObserver(
                forName: .AVCaptureDeviceWasDisconnected,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    CameraManager.shared.handleDeviceChange()
                }
            }
        ]
    }

    private func handleDeviceChange() {
        refreshAvailableDevices()
        let needsReconfigure = shouldReconfigureForPreferredDevice()
        if needsReconfigure {
            resetSessionConfiguration()
        }
        if activePreviewCount > 0 && (!isConfigured || needsReconfigure) {
            startSessionIfNeeded()
        }
    }

    private func normalizedDeviceID(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return raw
    }

    private func isExternalCamera(_ device: AVCaptureDevice) -> Bool {
        if #available(macOS 14.0, *) {
            return device.deviceType == .external
        }
        return device.deviceType.rawValue == "AVCaptureDeviceTypeExternalUnknown"
    }
}
