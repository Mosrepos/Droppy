//
//  AIInstallManager.swift
//  Droppy
//
//  Created by Droppy on 11/01/2026.
//  Manages installation of external BiRefNet runtime + model
//

import Foundation
import Combine
import CryptoKit

private enum AIInstallValidationError: LocalizedError {
    case timedOut

    var errorDescription: String? {
        switch self {
        case .timedOut:
            return "Validation timed out."
        }
    }
}

private final class AIModelDownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    private let onProgress: @Sendable (Int64, Int64) -> Void

    init(onProgress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.onProgress = onProgress
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onProgress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Required by URLSessionDownloadDelegate; result is already returned by download(for:delegate:).
    }
}

@MainActor
final class AIInstallManager: ObservableObject {
    static let shared = AIInstallManager()

    // Legacy key retained for cleanup compatibility with previous Python pipeline.
    static let selectedPythonPathKey = "aiBackgroundRemovalPythonPath"

    nonisolated static let modelVersion = "birefnet-general-epoch_244"
    nonisolated static let modelURL = "https://github.com/danielgatis/rembg/releases/download/v0.0.0/BiRefNet-general-epoch_244.onnx"
    nonisolated static let modelFileName = "birefnet-general.onnx"
    nonisolated static let modelSHA256 = "58f621f00f5d756097615970a88a791584600dcf7c45b18a0a6267535a1ebd3c"
    nonisolated static let modelByteSize: Int64 = 972_666_916

    nonisolated static var managedAssetsURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Droppy", isDirectory: true)
            .appendingPathComponent("AIBackgroundRemoval", isDirectory: true)
    }

    nonisolated static var managedModelsURL: URL {
        managedAssetsURL.appendingPathComponent("models", isDirectory: true)
    }

    nonisolated static var localModelURL: URL {
        managedModelsURL.appendingPathComponent(modelFileName, isDirectory: false)
    }

    nonisolated static var localModelPath: String {
        localModelURL.path
    }

    nonisolated static var legacyVenvURL: URL {
        managedAssetsURL.appendingPathComponent("venv", isDirectory: true)
    }

    nonisolated static var legacyCheckpointURL: URL {
        managedModelsURL.appendingPathComponent("ckpt_base.pth", isDirectory: false)
    }

    @Published var isInstalled = false
    @Published var isInstalling = false
    @Published var installProgress: String = ""
    @Published var installProgressFraction: Double = 0
    @Published var installProgressDetail: String = ""
    @Published var installError: String?

    private let installedCacheKey = "aiBackgroundRemovalInstalled"
    private let legacyRuntimeFlagKey = "useLocalBackgroundRemoval"
    private let validationTimeoutSeconds: TimeInterval = 120
    private let runtimeManager = AIBackgroundRemovalRuntimeManager.shared
    private var cancellables = Set<AnyCancellable>()

    private init() {
        isInstalled = UserDefaults.standard.bool(forKey: installedCacheKey)
        installProgressFraction = isInstalled ? 1.0 : 0
        installProgressDetail = isInstalled ? "Runtime + model are ready." : ""
        bindRuntimeState()
        checkInstallationStatus()
    }

    var modelDownloadURL: String {
        Self.modelURL
    }

    var modelFormattedSize: String {
        ByteCountFormatter.string(fromByteCount: Self.modelByteSize, countStyle: .file)
    }

    func checkInstallationStatus() {
        let runtimeLikelyReady = runtimeManager.isInstalled && runtimeManager.executableURL != nil
        let modelLikelyReady = Self.modelSizeMatchesManifest()
        if runtimeLikelyReady && modelLikelyReady {
            setInstalledState(true)
        } else if !isInstalling {
            setInstalledState(false)
        }

        Task {
            let ready = await runtimeReady(requireValidation: false)
            setInstalledState(ready)
        }
    }

    func installTransparentBackground() async {
        isInstalling = true
        setInstallProgress(
            step: "Checking runtime…",
            fraction: 0.05,
            detail: "Verifying external runtime and model files…"
        )
        installError = nil

        defer {
            isInstalling = false
            checkInstallationStatus()
        }

        let initialRuntimeReady = await runtimeReady(requireValidation: true)
        if initialRuntimeReady {
            setInstallProgress(
                step: "Installation complete!",
                fraction: 1.0,
                detail: "Runtime + model are ready."
            )
            setInstalledState(true)
            return
        }

        let hasValidModelAlready = await Self.modelMatchesManifestAsync()
        let shouldReinstallRuntime = !runtimeManager.isInstalled || (hasValidModelAlready && !initialRuntimeReady)
        if shouldReinstallRuntime {
            setInstallProgress(
                step: "Checking runtime…",
                fraction: 0.08,
                detail: "Installing background removal runtime…"
            )
            do {
                try await runtimeManager.installOrUpdateRuntime()
            } catch {
                installProgress = ""
                installProgressDetail = ""
                installError = "Runtime install failed: \(error.localizedDescription)"
                return
            }
        }

        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: Self.managedModelsURL, withIntermediateDirectories: true)
        } catch {
            installProgress = ""
            installProgressDetail = ""
            installError = "Could not create AI model storage directory."
            return
        }

        let minimumFreeBytes = Self.modelByteSize + 512_000_000
        guard hasEnoughDiskSpace(requiredBytes: minimumFreeBytes) else {
            installProgress = ""
            installProgressDetail = ""
            installError = "Not enough disk space. Free at least \(ByteCountFormatter.string(fromByteCount: minimumFreeBytes, countStyle: .file)) and retry."
            return
        }

        if fileManager.fileExists(atPath: Self.localModelPath) {
            let matchesManifest = await Self.modelMatchesManifestAsync()
            if !matchesManifest {
                try? fileManager.removeItem(at: Self.localModelURL)
            }
        }

        if !fileManager.fileExists(atPath: Self.localModelPath) {
            guard let sourceURL = URL(string: Self.modelURL) else {
                installProgress = ""
                installProgressDetail = ""
                installError = "Model URL is invalid."
                return
            }

            setInstallProgress(
                step: "Downloading model…",
                fraction: 0.1,
                detail: "0% • 0 KB / \(Self.byteCountString(Self.modelByteSize))"
            )
            do {
                let (temporaryURL, response) = try await downloadModel(from: sourceURL)

                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    if httpResponse.statusCode == 404 {
                        installError = "Model download URL is unavailable (HTTP 404). Update Droppy and retry."
                    } else {
                        installError = "Model download failed with HTTP \(httpResponse.statusCode)."
                    }
                    installProgress = ""
                    installProgressDetail = ""
                    return
                }

                if fileManager.fileExists(atPath: Self.localModelPath) {
                    try? fileManager.removeItem(at: Self.localModelURL)
                }

                try fileManager.moveItem(at: temporaryURL, to: Self.localModelURL)
            } catch {
                installProgress = ""
                installProgressDetail = ""
                installError = "Failed to download BiRefNet model. Check your network and retry."
                return
            }
        }

        setInstallProgress(
            step: "Downloading model…",
            fraction: 0.85,
            detail: "Verifying model integrity…"
        )
        guard await Self.modelMatchesManifestAsync() else {
            installProgress = ""
            installProgressDetail = ""
            installError = "Downloaded model failed integrity verification."
            try? fileManager.removeItem(at: Self.localModelURL)
            return
        }

        setInstallProgress(
            step: "Validating model…",
            fraction: 0.9,
            detail: "Validating external runtime…"
        )
        let validationPulseTask = makeValidationPulseTask()
        defer { validationPulseTask.cancel() }
        do {
            try await validateRuntimeWithTimeout()
        } catch {
            installProgress = ""
            installProgressDetail = ""
            if let validationError = error as? AIInstallValidationError, case .timedOut = validationError {
                installError = "Model validation timed out. Retry install."
            } else {
                installError = "Model validation failed: \(error.localizedDescription)"
            }
            return
        }

        setInstallProgress(
            step: "Installation complete!",
            fraction: 1.0,
            detail: "BiRefNet runtime + model are ready."
        )
        setInstalledState(true)
        UserDefaults.standard.set(true, forKey: legacyRuntimeFlagKey)
        AnalyticsService.shared.trackExtensionActivation(extensionId: "aiBackgroundRemoval")
    }

    func uninstallTransparentBackground() async {
        isInstalling = true
        setInstallProgress(
            step: "Removing model…",
            fraction: 0,
            detail: "Cleaning up model artifacts…"
        )
        installError = nil

        defer {
            isInstalling = false
            checkInstallationStatus()
        }

        do {
            try removeManagedRuntimeArtifacts()
            try await runtimeManager.uninstallRuntime()
            setInstalledState(false)
            UserDefaults.standard.set(false, forKey: legacyRuntimeFlagKey)
            setInstallProgress(step: "", fraction: 0, detail: "")
        } catch {
            installProgress = ""
            installProgressDetail = ""
            installError = "Failed to remove AI model files: \(error.localizedDescription)"
        }
    }

    func cleanup() {
        Task {
            await uninstallTransparentBackground()

            UserDefaults.standard.removeObject(forKey: installedCacheKey)
            UserDefaults.standard.removeObject(forKey: Self.selectedPythonPathKey)
            UserDefaults.standard.removeObject(forKey: legacyRuntimeFlagKey)
            UserDefaults.standard.removeObject(forKey: "aiBackgroundRemovalTracked")

            isInstalled = false
            installProgress = ""
            installProgressFraction = 0
            installProgressDetail = ""
            installError = nil

            NotificationCenter.default.post(name: .extensionStateChanged, object: ExtensionType.aiBackgroundRemoval)
            print("[AIInstallManager] Cleanup complete")
        }
    }

    nonisolated static func modelExists() -> Bool {
        FileManager.default.fileExists(atPath: localModelPath)
    }

    nonisolated static func modelSizeMatchesManifest() -> Bool {
        guard FileManager.default.fileExists(atPath: localModelPath) else { return false }
        let attrs = try? FileManager.default.attributesOfItem(atPath: localModelPath)
        let fileSize = (attrs?[.size] as? NSNumber)?.int64Value ?? -1
        return fileSize == modelByteSize
    }

    nonisolated static func modelMatchesManifest() -> Bool {
        guard modelSizeMatchesManifest() else { return false }

        guard let digest = sha256Hex(forFileAt: localModelURL) else { return false }
        return digest == modelSHA256
    }

    private func setInstalledState(_ installed: Bool) {
        let previous = isInstalled

        isInstalled = installed
        UserDefaults.standard.set(installed, forKey: installedCacheKey)

        if installed {
            installError = nil
            installProgressFraction = 1.0
            if installProgress.isEmpty {
                installProgress = "Installation complete!"
            }
            if installProgressDetail.isEmpty {
                installProgressDetail = "Runtime + model are ready."
            }
        } else if !isInstalling {
            installProgressFraction = 0
            if installError == nil {
                installProgress = ""
                installProgressDetail = ""
            }
        }

        if previous != installed {
            NotificationCenter.default.post(name: .extensionStateChanged, object: ExtensionType.aiBackgroundRemoval)
        }
    }

    nonisolated private static func modelMatchesManifestAsync() async -> Bool {
        await Task.detached(priority: .utility) {
            modelMatchesManifest()
        }.value
    }

    private func runtimeReady(requireValidation: Bool) async -> Bool {
        guard await runtimeHelperReady(requirePing: requireValidation) else { return false }
        guard await Self.modelMatchesManifestAsync() else { return false }

        if requireValidation {
            do {
                _ = try await runtimeManager.runCommand(
                    "validateRuntime",
                    arguments: ["modelPath": Self.localModelPath]
                )
            } catch {
                return false
            }
        }

        return true
    }

    private func runtimeHelperReady(requirePing: Bool) async -> Bool {
        guard runtimeManager.isInstalled else { return false }
        guard runtimeManager.executableURL != nil else { return false }
        guard requirePing else { return true }

        do {
            _ = try await runtimeManager.runCommand("status")
            return true
        } catch {
            return false
        }
    }

    private func bindRuntimeState() {
        runtimeManager.$state
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .installed, .updateAvailable, .notInstalled:
                    self.checkInstallationStatus()
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    private func setInstallProgress(step: String, fraction: Double, detail: String) {
        installProgress = step
        installProgressFraction = max(0, min(1, fraction))
        installProgressDetail = detail
    }

    private func updateDownloadProgress(writtenBytes: Int64, expectedBytes: Int64) {
        let totalBytes = expectedBytes > 0 ? expectedBytes : Self.modelByteSize
        guard totalBytes > 0 else { return }

        let fraction = max(0, min(1, Double(writtenBytes) / Double(totalBytes)))
        let mappedProgress = 0.1 + (fraction * 0.75)
        installProgressFraction = max(installProgressFraction, mappedProgress)
        installProgressDetail = "\(Int(fraction * 100))% • \(Self.byteCountString(writtenBytes)) / \(Self.byteCountString(totalBytes))"
    }

    private func downloadModel(from sourceURL: URL) async throws -> (URL, URLResponse) {
        let progressDelegate = AIModelDownloadProgressDelegate { [weak self] written, expected in
            Task { @MainActor [weak self] in
                self?.updateDownloadProgress(writtenBytes: written, expectedBytes: expected)
            }
        }

        var request = URLRequest(url: sourceURL)
        request.timeoutInterval = 3_600
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return try await URLSession.shared.download(for: request, delegate: progressDelegate)
    }

    private func makeValidationPulseTask() -> Task<Void, Never> {
        Task { [weak self] in
            let messages = [
                "Launching external runtime…",
                "Running runtime warmup…",
                "Finalizing runtime validation…"
            ]
            var messageIndex = 0

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000)
                await MainActor.run {
                    guard let self, self.isInstalling else { return }
                    self.installProgressFraction = min(max(self.installProgressFraction, 0.9) + 0.005, 0.985)
                    self.installProgressDetail = messages[messageIndex % messages.count]
                    messageIndex += 1
                }
            }
        }
    }

    private func validateRuntimeWithTimeout() async throws {
        let validationTask = Task(priority: .userInitiated) { [runtimeManager] in
            _ = try await runtimeManager.runCommand(
                "validateRuntime",
                arguments: ["modelPath": Self.localModelPath]
            )
        }

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await validationTask.value
                }

                group.addTask { [validationTimeoutSeconds] in
                    try await Task.sleep(nanoseconds: UInt64(validationTimeoutSeconds * 1_000_000_000))
                    throw AIInstallValidationError.timedOut
                }

                _ = try await group.next()
                group.cancelAll()
            }
        } catch AIInstallValidationError.timedOut {
            validationTask.cancel()
            throw AIInstallValidationError.timedOut
        } catch {
            validationTask.cancel()
            throw error
        }
    }

    nonisolated private static func byteCountString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func hasEnoughDiskSpace(requiredBytes: Int64) -> Bool {
        let probeURL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let values = try? probeURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let available = values?.volumeAvailableCapacityForImportantUsage else {
            return true
        }
        return Int64(available) >= requiredBytes
    }

    private func removeManagedRuntimeArtifacts() throws {
        let fileManager = FileManager.default

        let runtimeArtifacts: [URL] = [
            Self.localModelURL,
            Self.legacyCheckpointURL,
            Self.legacyVenvURL
        ]

        for artifact in runtimeArtifacts where fileManager.fileExists(atPath: artifact.path) {
            try fileManager.removeItem(at: artifact)
        }

        if fileManager.fileExists(atPath: Self.managedModelsURL.path),
           (try? fileManager.contentsOfDirectory(atPath: Self.managedModelsURL.path).isEmpty) == true {
            try? fileManager.removeItem(at: Self.managedModelsURL)
        }
    }

    nonisolated private static func sha256Hex(forFileAt url: URL) -> String? {
        guard let stream = InputStream(url: url) else { return nil }
        stream.open()
        defer { stream.close() }

        var hasher = SHA256()
        let bufferSize = 1_048_576
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        while stream.hasBytesAvailable {
            let bytesRead = stream.read(&buffer, maxLength: buffer.count)
            if bytesRead < 0 {
                return nil
            }
            if bytesRead == 0 {
                break
            }
            hasher.update(data: Data(buffer[0..<bytesRead]))
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
