//
//  VoiceTranscribeManager.swift
//  Droppy
//
//  Core manager for audio recording and transcription using external runtime helper
//

import SwiftUI
@preconcurrency import AVFoundation
import Combine
import UniformTypeIdentifiers
import CryptoKit

private nonisolated final class VoiceRuntimeOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private let limit: Int

    init(limit: Int = 2 * 1024 * 1024) {
        self.limit = limit
    }

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        if data.count > limit {
            data.removeFirst(data.count - limit)
        }
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        let snapshot = data
        lock.unlock()
        return snapshot
    }
}

// MARK: - Transcription Model

enum WhisperModel: String, CaseIterable, Identifiable {
    case tiny = "openai_whisper-tiny"
    case base = "openai_whisper-base"
    case small = "openai_whisper-small"
    case medium = "openai_whisper-medium"
    case large = "openai_whisper-large-v3"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .tiny: return "Tiny (~75 MB)"
        case .base: return "Base (~142 MB)"
        case .small: return "Small (~466 MB)"
        case .medium: return "Medium (~1.5 GB)"
        case .large: return "Large (~3 GB)"
        }
    }
    
    var sizeDescription: String {
        switch self {
        case .tiny: return "Fastest, basic accuracy"
        case .base: return "Fast, good accuracy"
        case .small: return "Balanced speed & accuracy"
        case .medium: return "Slow, high accuracy"
        case .large: return "Slowest, best accuracy"
        }
    }
}

// MARK: - Recording State

enum VoiceRecordingState: Equatable {
    case idle
    case recording
    case processing
    case complete
    case error(String)
    
    static func == (lhs: VoiceRecordingState, rhs: VoiceRecordingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.recording, .recording), (.processing, .processing), (.complete, .complete):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - External Runtime (GitHub Releases)

enum VoiceRuntimeInstallState: Equatable {
    case checking
    case notInstalled
    case installing(progress: Double)
    case installed(version: String)
    case updateAvailable(currentVersion: String, latestVersion: String)
    case failed(String)
}

private struct VoiceRuntimeManifest: Codable {
    struct Artifact: Codable {
        let arch: String
        let url: URL
        let sha256: String
        let sizeBytes: Int64
        let teamID: String
    }

    let id: String
    let version: String
    let protocolVersion: Int
    let minAppVersion: String?
    let executableName: String
    let artifacts: [Artifact]
}

@MainActor
final class VoiceTranscribeRuntimeManager: ObservableObject {
    static let shared = VoiceTranscribeRuntimeManager()

    @Published private(set) var state: VoiceRuntimeInstallState = .checking
    @Published private(set) var installedVersion: String?
    @Published private(set) var latestVersion: String?
    @Published private(set) var lastError: String?

    private let installedVersionKey = "voiceTranscribeRuntimeInstalledVersion"
    private let installedExecutableKey = "voiceTranscribeRuntimeInstalledExecutablePath"
    private let latestVersionKey = "voiceTranscribeRuntimeLatestVersion"
    private let manifestBaseURLString = "https://github.com/iordv/Droppy/releases/download/voice-runtime/voice-transcribe-runtime-manifest.txt"
    private let expectedExtensionID = "voiceTranscribe"
    private let expectedProtocolVersion = 1

    private var installTask: Task<Void, Never>?

    private init() {
        installedVersion = UserDefaults.standard.string(forKey: installedVersionKey)
        latestVersion = UserDefaults.standard.string(forKey: latestVersionKey)
        recomputeStateWithoutNetwork()
        Task { await refresh() }
    }

    var isInstalled: Bool {
        switch state {
        case .installed, .updateAvailable:
            return true
        default:
            return false
        }
    }

    var isInstalling: Bool {
        if case .installing = state { return true }
        return false
    }

    var installProgress: Double {
        if case .installing(let progress) = state { return progress }
        return 0
    }

    var executableURL: URL? {
        guard let executablePath = UserDefaults.standard.string(forKey: installedExecutableKey),
              !executablePath.isEmpty else {
            return nil
        }
        let url = URL(fileURLWithPath: executablePath, isDirectory: false)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func refresh() async {
        state = .checking
        lastError = nil

        guard let manifestURL = manifestURL() else {
            state = .failed("Runtime manifest URL is invalid.")
            lastError = "Runtime manifest URL is invalid."
            return
        }

        do {
            let manifest = try await fetchManifest(from: manifestURL)
            latestVersion = manifest.version
            UserDefaults.standard.set(manifest.version, forKey: latestVersionKey)
            try validateManifest(manifest)

            guard let artifact = artifactForCurrentArchitecture(from: manifest) else {
                throw RuntimeInstallError.unsupportedArchitecture(Self.currentArchitecture)
            }

            if let installedVersion = installedVersion,
               let executableURL = executableURL,
               FileManager.default.fileExists(atPath: executableURL.path) {
                if installedVersion.compare(manifest.version, options: .numeric) == .orderedAscending {
                    state = .updateAvailable(currentVersion: installedVersion, latestVersion: manifest.version)
                } else {
                    state = .installed(version: installedVersion)
                }
            } else {
                _ = artifact
                state = .notInstalled
            }
        } catch {
            // Offline install should keep already-installed runtime available.
            if let installedVersion = installedVersion, executableURL != nil {
                state = .installed(version: installedVersion)
            } else {
                let message = friendlyErrorMessage(error)
                state = .failed(message)
                lastError = message
            }
        }
    }

    func installOrUpdateRuntime() {
        guard !isInstalling else { return }

        installTask?.cancel()
        installTask = Task { [weak self] in
            guard let self else { return }
            await self.performInstallOrUpdate()
            self.installTask = nil
        }
    }

    func cancelInstall() {
        installTask?.cancel()
        installTask = nil
        recomputeStateWithoutNetwork()
    }

    func uninstallRuntime() async {
        installTask?.cancel()
        installTask = nil

        let fileManager = FileManager.default
        let root = Self.runtimeInstallRoot
        do {
            if fileManager.fileExists(atPath: root.path) {
                try fileManager.removeItem(at: root)
            }
            UserDefaults.standard.removeObject(forKey: installedVersionKey)
            UserDefaults.standard.removeObject(forKey: installedExecutableKey)
            installedVersion = nil
            state = .notInstalled
            NotificationCenter.default.post(name: .extensionStateChanged, object: ExtensionType.voiceTranscribe)
        } catch {
            let message = "Failed to remove runtime files: \(error.localizedDescription)"
            state = .failed(message)
            lastError = message
        }
    }

    private func performInstallOrUpdate() async {
        do {
            guard let manifestURL = manifestURL() else {
                throw RuntimeInstallError.invalidManifestURL
            }
            state = .installing(progress: 0.02)
            let manifest = try await fetchManifest(from: manifestURL)
            latestVersion = manifest.version
            UserDefaults.standard.set(manifest.version, forKey: latestVersionKey)

            try validateManifest(manifest)
            try Task.checkCancellation()

            guard let artifact = artifactForCurrentArchitecture(from: manifest) else {
                throw RuntimeInstallError.unsupportedArchitecture(Self.currentArchitecture)
            }

            if let minAppVersion = manifest.minAppVersion {
                let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
                if currentVersion.compare(minAppVersion, options: .numeric) == .orderedAscending {
                    throw RuntimeInstallError.appVersionTooOld(required: minAppVersion, current: currentVersion)
                }
            }

            state = .installing(progress: 0.08)

            let tempRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("DroppyVoiceRuntimeInstall-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempRoot) }

            let archiveURL = tempRoot.appendingPathComponent("runtime.tar.gz", isDirectory: false)
            let extractedURL = tempRoot.appendingPathComponent("extracted", isDirectory: true)
            try FileManager.default.createDirectory(at: extractedURL, withIntermediateDirectories: true)

            state = .installing(progress: 0.12)
            let downloadedData = try await downloadArtifactData(from: artifact.url)
            try Task.checkCancellation()

            state = .installing(progress: 0.45)
            try verifySHA256(data: downloadedData, expectedHex: artifact.sha256)
            try downloadedData.write(to: archiveURL, options: .atomic)
            try Task.checkCancellation()

            state = .installing(progress: 0.58)
            _ = try await runProcess("/usr/bin/tar", arguments: ["-xzf", archiveURL.path, "-C", extractedURL.path])
            try Task.checkCancellation()

            state = .installing(progress: 0.70)
            let runtimeRoot = try resolveRuntimeRoot(in: extractedURL)
            let executableURL = try resolveExecutable(named: manifest.executableName, in: runtimeRoot)
            let executableRelativePath = try relativePath(for: executableURL, root: runtimeRoot)
            try ensureExecutableBit(at: executableURL)
            try await verifyCodeSignature(at: executableURL, expectedTeamID: artifact.teamID)
            try Task.checkCancellation()

            state = .installing(progress: 0.86)
            try installAtomically(runtimeRoot: runtimeRoot, version: manifest.version)
            let installedExecutableURL = Self.runtimeInstallRoot
                .appendingPathComponent(manifest.version, isDirectory: true)
                .appendingPathComponent(executableRelativePath, isDirectory: false)

            UserDefaults.standard.set(manifest.version, forKey: installedVersionKey)
            UserDefaults.standard.set(installedExecutableURL.path, forKey: installedExecutableKey)
            installedVersion = manifest.version
            lastError = nil

            state = .installed(version: manifest.version)
            NotificationCenter.default.post(name: .extensionStateChanged, object: ExtensionType.voiceTranscribe)
            AnalyticsService.shared.trackExtensionActivation(extensionId: "voiceTranscribeRuntime")
        } catch is CancellationError {
            recomputeStateWithoutNetwork()
        } catch {
            let message = friendlyErrorMessage(error)
            state = .failed(message)
            lastError = message
        }
    }

    private func recomputeStateWithoutNetwork() {
        if let installedVersion = UserDefaults.standard.string(forKey: installedVersionKey),
           let executablePath = UserDefaults.standard.string(forKey: installedExecutableKey),
           FileManager.default.fileExists(atPath: executablePath) {
            self.installedVersion = installedVersion
            if let latestVersion = UserDefaults.standard.string(forKey: latestVersionKey),
               installedVersion.compare(latestVersion, options: .numeric) == .orderedAscending {
                state = .updateAvailable(currentVersion: installedVersion, latestVersion: latestVersion)
            } else {
                state = .installed(version: installedVersion)
            }
            return
        }

        state = .notInstalled
        installedVersion = nil
    }

    private func validateManifest(_ manifest: VoiceRuntimeManifest) throws {
        guard manifest.id == expectedExtensionID else {
            throw RuntimeInstallError.invalidManifest("Unexpected extension id '\(manifest.id)'.")
        }
        guard manifest.protocolVersion == expectedProtocolVersion else {
            throw RuntimeInstallError.invalidManifest(
                "Unsupported protocol version \(manifest.protocolVersion). Expected \(expectedProtocolVersion)."
            )
        }
        guard !manifest.executableName.isEmpty else {
            throw RuntimeInstallError.invalidManifest("Manifest executable name is empty.")
        }
        guard !manifest.artifacts.isEmpty else {
            throw RuntimeInstallError.invalidManifest("Manifest has no artifacts.")
        }
    }

    private func manifestURL() -> URL? {
        guard var components = URLComponents(string: manifestBaseURLString) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "cb", value: String(Int(Date().timeIntervalSince1970)))
        ]
        return components.url
    }

    private func fetchManifest(from url: URL) async throws -> VoiceRuntimeManifest {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw RuntimeInstallError.network("Manifest response was invalid.")
        }
        guard (200...299).contains(http.statusCode) else {
            throw RuntimeInstallError.network("Manifest request failed with HTTP \(http.statusCode).")
        }
        do {
            return try JSONDecoder().decode(VoiceRuntimeManifest.self, from: data)
        } catch {
            throw RuntimeInstallError.invalidManifest("Manifest could not be decoded.")
        }
    }

    private func artifactForCurrentArchitecture(from manifest: VoiceRuntimeManifest) -> VoiceRuntimeManifest.Artifact? {
        manifest.artifacts.first(where: { $0.arch == Self.currentArchitecture })
    }

    private func downloadArtifactData(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw RuntimeInstallError.network("Runtime download response was invalid.")
        }
        guard (200...299).contains(http.statusCode) else {
            throw RuntimeInstallError.network("Runtime download failed with HTTP \(http.statusCode).")
        }
        return data
    }

    private func verifySHA256(data: Data, expectedHex: String) throws {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest.lowercased() == expectedHex.lowercased() else {
            throw RuntimeInstallError.checksumMismatch
        }
    }

    private func resolveRuntimeRoot(in extractedURL: URL) throws -> URL {
        let topLevel = try FileManager.default.contentsOfDirectory(
            at: extractedURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        if topLevel.count == 1 {
            let candidate = topLevel[0]
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return candidate
            }
        }

        return extractedURL
    }

    private func resolveExecutable(named executableName: String, in root: URL) throws -> URL {
        let directPath = root.appendingPathComponent(executableName, isDirectory: false)
        if FileManager.default.fileExists(atPath: directPath.path) {
            return directPath
        }

        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let candidate = enumerator?.nextObject() as? URL {
            if candidate.lastPathComponent == executableName {
                return candidate
            }
        }

        throw RuntimeInstallError.executableMissing(executableName)
    }

    private func relativePath(for fileURL: URL, root: URL) throws -> String {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let filePath = fileURL.path
        guard filePath.hasPrefix(rootPath) else {
            throw RuntimeInstallError.invalidManifest("Runtime executable path was outside extracted package.")
        }
        return String(filePath.dropFirst(rootPath.count))
    }

    private func ensureExecutableBit(at executableURL: URL) throws {
        var attributes = try FileManager.default.attributesOfItem(atPath: executableURL.path)
        let currentPermissions = attributes[.posixPermissions] as? NSNumber
        let value = (currentPermissions?.uint16Value ?? 0o755) | 0o111
        attributes[.posixPermissions] = NSNumber(value: value)
        try FileManager.default.setAttributes(attributes, ofItemAtPath: executableURL.path)
    }

    private func verifyCodeSignature(at executableURL: URL, expectedTeamID: String) async throws {
        let (_, stdErr) = try await runProcess(
            "/usr/bin/codesign",
            arguments: ["-dv", "--verbose=4", executableURL.path]
        )

        let lines = stdErr.split(separator: "\n").map(String.init)
        guard let teamLine = lines.first(where: { $0.hasPrefix("TeamIdentifier=") }) else {
            throw RuntimeInstallError.signatureInvalid("No TeamIdentifier found.")
        }
        let teamID = teamLine.replacingOccurrences(of: "TeamIdentifier=", with: "")
        guard teamID == expectedTeamID else {
            throw RuntimeInstallError.signatureInvalid("Unexpected TeamIdentifier '\(teamID)'.")
        }
    }

    private func installAtomically(runtimeRoot: URL, version: String) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: Self.runtimeInstallRoot, withIntermediateDirectories: true)

        let destination = Self.runtimeInstallRoot.appendingPathComponent(version, isDirectory: true)
        let tempDestination = Self.runtimeInstallRoot.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)

        if fileManager.fileExists(atPath: tempDestination.path) {
            try fileManager.removeItem(at: tempDestination)
        }

        try fileManager.copyItem(at: runtimeRoot, to: tempDestination)

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        try fileManager.moveItem(at: tempDestination, to: destination)
    }

    private func runProcess(_ executablePath: String, arguments: [String]) async throws -> (String, String) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments

            let out = Pipe()
            let err = Pipe()
            process.standardOutput = out
            process.standardError = err

            process.terminationHandler = { proc in
                let stdOutData = out.fileHandleForReading.readDataToEndOfFile()
                let stdErrData = err.fileHandleForReading.readDataToEndOfFile()
                let stdOut = String(data: stdOutData, encoding: .utf8) ?? ""
                let stdErr = String(data: stdErrData, encoding: .utf8) ?? ""

                if proc.terminationStatus == 0 {
                    continuation.resume(returning: (stdOut, stdErr))
                } else {
                    continuation.resume(throwing: RuntimeInstallError.processFailed(
                        command: executablePath,
                        status: proc.terminationStatus,
                        errorOutput: stdErr.isEmpty ? stdOut : stdErr
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func friendlyErrorMessage(_ error: Error) -> String {
        if let runtimeError = error as? RuntimeInstallError {
            return runtimeError.errorDescription ?? "Runtime installation failed."
        }
        return error.localizedDescription
    }

    private enum RuntimeInstallError: LocalizedError {
        case invalidManifestURL
        case invalidManifest(String)
        case unsupportedArchitecture(String)
        case appVersionTooOld(required: String, current: String)
        case network(String)
        case checksumMismatch
        case executableMissing(String)
        case signatureInvalid(String)
        case processFailed(command: String, status: Int32, errorOutput: String)

        var errorDescription: String? {
            switch self {
            case .invalidManifestURL:
                return "Runtime manifest URL is invalid."
            case .invalidManifest(let message):
                return "Invalid runtime manifest: \(message)"
            case .unsupportedArchitecture(let arch):
                return "No runtime artifact available for architecture '\(arch)'."
            case .appVersionTooOld(let required, let current):
                return "This runtime requires Droppy \(required)+ (current: \(current))."
            case .network(let message):
                return message
            case .checksumMismatch:
                return "Runtime checksum verification failed."
            case .executableMissing(let name):
                return "Runtime executable '\(name)' was not found in package."
            case .signatureInvalid(let message):
                return "Runtime signature verification failed: \(message)"
            case .processFailed(_, _, let errorOutput):
                let trimmed = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "Runtime install command failed." : trimmed
            }
        }
    }

    private static var runtimeInstallRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Droppy", isDirectory: true)
            .appendingPathComponent("Extensions", isDirectory: true)
            .appendingPathComponent("voiceTranscribe", isDirectory: true)
    }

    private static var currentArchitecture: String {
#if arch(arm64)
        return "arm64"
#elseif arch(x86_64)
        return "x86_64"
#else
        return "unknown"
#endif
    }
}

// MARK: - Voice Transcribe Manager

@MainActor
final class VoiceTranscribeManager: ObservableObject {
    static let shared = VoiceTranscribeManager()
    
    // MARK: - Published Properties
    
    @Published var state: VoiceRecordingState = .idle
    @Published var selectedModel: WhisperModel = .small {
        didSet {
            UserDefaults.standard.set(selectedModel.rawValue, forKey: "voiceTranscribeModel")
            Task { @MainActor in
                await refreshModelStatusFromRuntime()
            }
        }
    }
    @Published var isModelDownloaded: Bool = false
    @Published var downloadProgress: Double = 0
    @Published var transcriptionResult: String = ""
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0
    @Published var selectedLanguage: String = "auto"
    @Published var isMenuBarEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isMenuBarEnabled, forKey: "voiceTranscribeMenuBarEnabled")
            VoiceTranscribeMenuBar.shared.setVisible(isMenuBarEnabled)
        }
    }
    @Published var isDownloading: Bool = false
    @Published var transcriptionProgress: Double = 0
    @Published var transcriptionStatus: String = ""
    @Published var processingElapsed: TimeInterval = 0
    @Published var currentTranscriptionInputDuration: TimeInterval = 0
    @Published private(set) var lastRecordingURL: URL? // Available after transcription for save
    
    // Keyboard shortcuts for recording modes
    @Published var quickRecordShortcut: SavedShortcut? {
        didSet { saveShortcutPreferences() }
    }
    @Published var invisiRecordShortcut: SavedShortcut? {
        didSet { saveShortcutPreferences() }
    }
    
    // MARK: - Private Properties
    
    private var audioRecorder: AVAudioRecorder?
    private var recordingTimer: Timer?
    private var levelTimer: Timer?
    private var recordingURL: URL?
    private var downloadTask: Task<Void, Never>?
    private var transcriptionTask: Task<Void, Never>?
    private var quickRecordHotkey: GlobalHotKey?   // Carbon-based for reliability
    private var invisiRecordHotkey: GlobalHotKey?  // Carbon-based for reliability
    private var processingTimer: Timer?
    private var processingStartedAt: Date?
    private var lastObservedProgressAt: Date?
    private var warmingModels = Set<WhisperModel>()
    private var cancellables = Set<AnyCancellable>()
    private let runtimeManager = VoiceTranscribeRuntimeManager.shared
    
    // Model storage directory
    private var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let modelsDir = appSupport.appendingPathComponent("Droppy/WhisperModels")
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        return modelsDir
    }
    
    // Recording storage
    private var recordingsDirectory: URL {
        let tempDir = FileManager.default.temporaryDirectory
        return tempDir.appendingPathComponent("DroppyRecordings")
    }
    
    // Supported languages
    let supportedLanguages: [(code: String, name: String)] = [
        ("auto", "Auto Detect"),
        ("en", "English"),
        ("nl", "Dutch"),
        ("de", "German"),
        ("fr", "French"),
        ("es", "Spanish"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("pl", "Polish"),
        ("ru", "Russian"),
        ("zh", "Chinese"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("ar", "Arabic"),
        ("hi", "Hindi"),
        ("tr", "Turkish"),
        ("uk", "Ukrainian"),
        ("sv", "Swedish"),
        ("da", "Danish"),
        ("no", "Norwegian"),
        ("fi", "Finnish")
    ]
    
    // MARK: - Initialization
    
    private init() {
        try? FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        loadPreferences()
        bindRuntimeState()
        loadShortcutPreferences()
        checkModelStatus()
    }
    
    // MARK: - Public Methods

    private var runtimeMissingMessage: String {
        "Install the Voice Transcribe runtime in Extensions before using this feature."
    }

    private enum RuntimeIPCError: LocalizedError {
        case runtimeNotInstalled
        case executableMissing
        case invalidResponse(String)
        case helperError(String)
        case processFailed(String)

        var errorDescription: String? {
            switch self {
            case .runtimeNotInstalled:
                return "Runtime is not installed."
            case .executableMissing:
                return "Runtime executable is missing."
            case .invalidResponse(let details):
                return details
            case .helperError(let message):
                return message
            case .processFailed(let message):
                return message
            }
        }
    }

    private func runRuntimeCommand(_ action: String, arguments: [String: Any] = [:]) async throws -> [String: Any] {
        guard runtimeManager.isInstalled else {
            throw RuntimeIPCError.runtimeNotInstalled
        }
        guard let executableURL = runtimeManager.executableURL else {
            throw RuntimeIPCError.executableMissing
        }

        let requestObject: [String: Any] = [
            "action": action,
            "arguments": arguments
        ]

        let requestData = try JSONSerialization.data(withJSONObject: requestObject, options: [])

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = ["--json-rpc"]

            let stdIn = Pipe()
            let stdOut = Pipe()
            let stdErr = Pipe()
            process.standardInput = stdIn
            process.standardOutput = stdOut
            process.standardError = stdErr

            let stdoutBuffer = VoiceRuntimeOutputBuffer()
            let stderrBuffer = VoiceRuntimeOutputBuffer()

            stdOut.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    return
                }
                stdoutBuffer.append(chunk)
            }

            stdErr.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    return
                }
                stderrBuffer.append(chunk)
            }

            process.terminationHandler = { proc in
                stdOut.fileHandleForReading.readabilityHandler = nil
                stdErr.fileHandleForReading.readabilityHandler = nil

                let outRemainder = stdOut.fileHandleForReading.readDataToEndOfFile()
                let errRemainder = stdErr.fileHandleForReading.readDataToEndOfFile()
                stdoutBuffer.append(outRemainder)
                stderrBuffer.append(errRemainder)

                let outData = stdoutBuffer.snapshot()
                let errData = stderrBuffer.snapshot()

                let errText = String(data: errData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                guard proc.terminationStatus == 0 else {
                    let message = errText.isEmpty ? "Runtime command '\(action)' failed with exit \(proc.terminationStatus)." : errText
                    continuation.resume(throwing: RuntimeIPCError.processFailed(message))
                    return
                }

                guard let json = try? JSONSerialization.jsonObject(with: outData, options: []),
                      let dict = json as? [String: Any] else {
                    let outText = String(data: outData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let preview = [outText.prefix(240), errText.prefix(240)]
                        .map(String.init)
                        .filter { !$0.isEmpty }
                        .joined(separator: " | ")
                    let reason = preview.isEmpty ? "Runtime returned an invalid response." : "Runtime returned an invalid response: \(preview)"
                    continuation.resume(throwing: RuntimeIPCError.invalidResponse(reason))
                    return
                }

                if let ok = dict["ok"] as? Bool, ok == false {
                    let message = (dict["error"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let resolvedMessage = message.flatMap { $0.isEmpty ? nil : $0 } ?? "Runtime command failed."
                    continuation.resume(throwing: RuntimeIPCError.helperError(resolvedMessage))
                    return
                }

                if let payload = dict["payload"] as? [String: Any] {
                    continuation.resume(returning: payload)
                } else {
                    continuation.resume(returning: dict)
                }
            }

            do {
                try process.run()
                stdIn.fileHandleForWriting.write(requestData)
                stdIn.fileHandleForWriting.closeFile()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func refreshModelStatusFromRuntime() async {
        guard runtimeManager.isInstalled else {
            isModelDownloaded = false
            return
        }

        do {
            let result = try await runRuntimeCommand("status", arguments: ["model": selectedModel.rawValue])
            if let installed = result["installed"] as? Bool {
                isModelDownloaded = installed
            } else if let installedModels = result["installedModels"] as? [String] {
                isModelDownloaded = installedModels.contains(selectedModel.rawValue)
            } else {
                isModelDownloaded = false
            }

            if isModelDownloaded {
                savePreferences()
                warmModelInBackgroundIfNeeded(selectedModel)
            } else {
                UserDefaults.standard.removeObject(forKey: "voiceTranscribeModelDownloaded_\(selectedModel.rawValue)")
            }
        } catch {
            // Avoid resetting UI to "Download Model" during transient startup/runtime races.
            if isModelDownloaded {
                return
            }
            let cachedInstalled = UserDefaults.standard.bool(forKey: "voiceTranscribeModelDownloaded_\(selectedModel.rawValue)")
            isModelDownloaded = cachedInstalled
        }
    }
    
    /// Start recording audio
    func startRecording() {
        guard runtimeManager.isInstalled else {
            state = .error(runtimeMissingMessage)
            return
        }

        // Don't start if extension is disabled
        guard !ExtensionType.voiceTranscribe.isRemoved else {
            print("[VoiceTranscribe] Extension is disabled, ignoring")
            return
        }
        
        print("VoiceTranscribe: startRecording called, state: \(state), isModelDownloaded: \(isModelDownloaded)")
        
        guard state == .idle else {
            print("VoiceTranscribe: Cannot start recording - state is \(state), not idle")
            return
        }
        
        // Always request mic and start recording
        requestMicAndRecord()
    }
    
    private func requestMicAndRecord() {
        // Use AVAudioApplication for macOS 14+ or fallback to AVCaptureDevice
        if #available(macOS 14.0, *) {
            let status = AVAudioApplication.shared.recordPermission
            
            switch status {
            case .granted:
                print("VoiceTranscribe: Mic already authorized, beginning recording")
                beginRecording()
                
            case .undetermined:
                // First time - this will trigger the system prompt
                print("VoiceTranscribe: Requesting mic permission for first time (AVAudioApplication)")
                AVAudioApplication.requestRecordPermission { [weak self] granted in
                    DispatchQueue.main.async {
                        if granted {
                            print("VoiceTranscribe: Mic access granted, beginning recording")
                            self?.beginRecording()
                        } else {
                            print("VoiceTranscribe: Mic access denied by user via system prompt")
                            self?.state = .idle
                            VoiceRecordingWindowController.shared.hideWindow()
                        }
                    }
                }
                
            case .denied:
                print("VoiceTranscribe: Mic access previously denied, showing alert")
                state = .idle
                showMicPermissionAlert()
                
            @unknown default:
                print("VoiceTranscribe: Unknown mic auth status")
                state = .error("Unable to check microphone permission.")
            }
        } else {
            // Fallback for older macOS
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            
            switch status {
            case .authorized:
                print("VoiceTranscribe: Mic already authorized, beginning recording")
                beginRecording()
                
            case .notDetermined:
                print("VoiceTranscribe: Requesting mic permission for first time")
                AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                    DispatchQueue.main.async {
                        if granted {
                            print("VoiceTranscribe: Mic access granted, beginning recording")
                            self?.beginRecording()
                        } else {
                            print("VoiceTranscribe: Mic access denied by user via system prompt")
                            self?.state = .idle
                            VoiceRecordingWindowController.shared.hideWindow()
                        }
                    }
                }
                
            case .denied, .restricted:
                print("VoiceTranscribe: Mic access previously denied, showing alert")
                state = .idle
                showMicPermissionAlert()
                
            @unknown default:
                print("VoiceTranscribe: Unknown mic auth status")
                state = .error("Unable to check microphone permission.")
            }
        }
    }
    
    private func showMicPermissionAlert() {
        // Open System Settings directly without custom Droppy dialog
        // macOS handles all permission prompts natively
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
        
        // Hide recording window since we can't record
        VoiceRecordingWindowController.shared.hideWindow()
    }
    
    /// Stop recording and start transcription
    func stopRecording() {
        guard case .recording = state else { return }
        
        audioRecorder?.stop()
        recordingTimer?.invalidate()
        levelTimer?.invalidate()
        recordingTimer = nil
        levelTimer = nil
        
        // Revert menu bar icon to normal
        VoiceTranscribeMenuBar.shared.setRecordingState(false)
        
        beginProcessingSession(
            inputDuration: recordingDuration,
            initialStatus: "Preparing recording…"
        )
        
        // Start transcription
        transcriptionTask?.cancel()
        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            await self.transcribeRecording()
            self.clearTranscriptionTaskReference()
        }
    }
    
    /// Toggle recording state
    func toggleRecording() {
        switch state {
        case .idle:
            startRecording()
        case .recording:
            stopRecording()
        case .complete, .error:
            reset()
        default:
            break
        }
    }
    
    /// Reset to idle state
    func reset() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        finishProcessingSession()
        state = .idle
        transcriptionResult = ""
        transcriptionProgress = 0
        recordingDuration = 0
        audioLevel = 0
    }
    
    /// Copy transcription to clipboard
    func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcriptionResult, forType: .string)
    }
    
    /// Save the last recording to a user-selected location
    func saveRecording() {
        guard let sourceURL = lastRecordingURL, FileManager.default.fileExists(atPath: sourceURL.path) else {
            print("VoiceTranscribe: No recording available to save")
            return
        }
        
        let savePanel = NSSavePanel()
        savePanel.title = "Save Audio Recording"
        savePanel.nameFieldStringValue = "recording_\(Date().formatted(date: .abbreviated, time: .shortened).replacingOccurrences(of: ":", with: "-")).wav"
        savePanel.allowedContentTypes = [.wav, .audio]
        savePanel.canCreateDirectories = true
        savePanel.level = .screenSaver // Match result window level
        
        savePanel.begin { response in
            guard response == .OK, let destinationURL = savePanel.url else { return }
            
            Task { @MainActor in
                do {
                    // Copy to user's selected location
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                    print("VoiceTranscribe: Recording saved to \(destinationURL.path)")
                } catch {
                    print("VoiceTranscribe: Failed to save recording: \(error)")
                }
            }
        }
    }
    
    /// Discard the last recording (clean up temp file)
    func discardRecording() {
        guard let url = lastRecordingURL else { return }
        try? FileManager.default.removeItem(at: url)
        lastRecordingURL = nil
        print("VoiceTranscribe: Recording discarded")
    }
    
    /// Retry transcription of the last recording
    func retryTranscription() {
        guard let url = lastRecordingURL, FileManager.default.fileExists(atPath: url.path) else {
            print("VoiceTranscribe: No recording available to retry")
            state = .error("No recording available to retry")
            return
        }
        
        beginProcessingSession(
            inputDuration: audioDuration(at: url),
            initialStatus: "Retrying transcription…"
        )
        recordingURL = url
        
        transcriptionTask?.cancel()
        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            await self.transcribeRecording()
            self.clearTranscriptionTaskReference()
        }
    }

    
    /// Transcribe an existing audio file
    func transcribeFile(at url: URL) {
        guard runtimeManager.isInstalled else {
            state = .error(runtimeMissingMessage)
            return
        }

        guard state == .idle else {
            print("VoiceTranscribe: Cannot transcribe file - not idle")
            return
        }
        
        beginProcessingSession(
            inputDuration: 0,
            initialStatus: "Preparing audio file…"
        )
        
        transcriptionTask?.cancel()
        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            await self.transcribeAudioFile(at: url)
            self.clearTranscriptionTaskReference()
        }
    }

    func cancelTranscription() {
        guard case .processing = state else { return }
        transcriptionTask?.cancel()
        transcriptionTask = nil
        if let recordingURL {
            lastRecordingURL = recordingURL
        }
        finishProcessingSession()
        state = .idle
    }
    
    /// Download and initialize the selected model
    func downloadModel() {
        guard runtimeManager.isInstalled else {
            state = .error(runtimeMissingMessage)
            return
        }

        guard !isDownloading else { return }
        
        isDownloading = true
        downloadProgress = 0.02
        
        downloadTask = Task {
            let progressPulseTask = Task { [weak self] in
                guard let self else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    guard self.isDownloading else { continue }
                    if self.downloadProgress < 0.985 {
                        self.downloadProgress = min(0.985, self.downloadProgress + 0.008)
                    }
                }
            }

            do {
                downloadProgress = 0.12
                _ = try await runRuntimeCommand("installModel", arguments: [
                    "model": selectedModel.rawValue
                ])
                try Task.checkCancellation()
                downloadProgress = 0.95

                await refreshModelStatusFromRuntime()
                if !isModelDownloaded {
                    throw RuntimeIPCError.helperError("Runtime did not report model as installed.")
                }

                downloadProgress = 1.0
                savePreferences()
                AnalyticsService.shared.trackExtensionActivation(extensionId: "voiceTranscribe")
                print("VoiceTranscribe: Model \(selectedModel.rawValue) installed via runtime helper")
                warmModelInBackgroundIfNeeded(selectedModel)
            } catch is CancellationError {
                print("VoiceTranscribe: Download cancelled by user")
                downloadProgress = 0
            } catch {
                print("VoiceTranscribe: Failed to install model: \(error)")
                state = .error("Failed to download model: \(error.localizedDescription)")
                isModelDownloaded = false
            }

            progressPulseTask.cancel()
            isDownloading = false
            downloadTask = nil
        }
    }
    
    /// Cancel the current model download
    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        downloadProgress = 0
        print("VoiceTranscribe: Download cancelled")
    }
    
    /// Delete the downloaded model from disk
    func deleteModel() {
        downloadTask?.cancel()
        downloadTask = nil
        isModelDownloaded = false
        isMenuBarEnabled = false
        downloadProgress = 0

        Task {
            do {
                _ = try await runRuntimeCommand("deleteModel", arguments: [
                    "model": selectedModel.rawValue
                ])
            } catch {
                print("VoiceTranscribe: Failed to delete model in runtime helper: \(error)")
            }
        }

        for model in WhisperModel.allCases {
            UserDefaults.standard.removeObject(forKey: "voiceTranscribeModelDownloaded_\(model.rawValue)")
            UserDefaults.standard.removeObject(forKey: "voiceTranscribeModelWarmed_\(model.rawValue)")
        }

        VoiceTranscribeMenuBar.shared.setVisible(false)
        print("VoiceTranscribe: Model deletion requested via runtime helper")
    }
    
    // MARK: - Private Methods
    
    private func beginRecording() {
        let fileName = "recording_\(Date().timeIntervalSince1970).wav"
        recordingURL = recordingsDirectory.appendingPathComponent(fileName)
        
        // Whisper requires 16kHz sample rate
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: recordingURL!, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            
            state = .recording
            recordingDuration = 0
            
            // Update menu bar icon to recording state
            VoiceTranscribeMenuBar.shared.setRecordingState(true)
            
            // Update duration timer
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.recordingDuration += 0.1
                }
            }
            
            // Update audio level timer
            levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.audioRecorder?.updateMeters()
                    let db = self?.audioRecorder?.averagePower(forChannel: 0) ?? -160
                    // Normalize dB to 0-1 range (-60 to 0 dB)
                    let normalized = max(0, min(1, (db + 60) / 60))
                    self?.audioLevel = Float(normalized)
                }
            }
        } catch {
            state = .error("Failed to start recording: \(error.localizedDescription)")
        }
    }
    
    private func transcribeRecording() async {
        guard let url = recordingURL else {
            finishProcessingSession()
            state = .error("No recording found")
            return
        }
        
        if case .processing = state {
            // already in processing state
        } else {
            beginProcessingSession(
                inputDuration: audioDuration(at: url),
                initialStatus: "Preparing recording…"
            )
        }
        setTranscriptionProgress(0.05, status: "Preparing recording…")

        do {
            setTranscriptionProgress(0.2, status: "Transcribing audio…")
            let result = try await runRuntimeCommand("transcribe", arguments: [
                "model": selectedModel.rawValue,
                "language": selectedLanguage,
                "audioPath": url.path
            ])
            try Task.checkCancellation()
            setTranscriptionProgress(0.98, status: "Finalizing transcript…")

            let text = (result["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                transcriptionResult = text
                lastRecordingURL = url
                print("VoiceTranscribe: Transcription complete - \(text.count) chars")
                presentTranscriptionResult()
            } else {
                transcriptionResult = ""
                lastRecordingURL = nil
                try? FileManager.default.removeItem(at: url)
            }

            finishProcessingSession()
            state = .idle
        } catch is CancellationError {
            finishProcessingSession()
            state = .idle
        } catch {
            print("VoiceTranscribe: Transcription error: \(error)")
            // Keep recording for retry
            lastRecordingURL = url
            finishProcessingSession()
            state = .error("Transcription failed: \(error.localizedDescription)")
        }
    }
    
    /// Transcribe an external audio file (does NOT delete the source file)
    private func transcribeAudioFile(at url: URL) async {
        setTranscriptionProgress(0.05, status: "Preparing audio file…")
        
        // Start security-scoped access (required for files from NSOpenPanel)
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }

        if currentTranscriptionInputDuration <= 0 {
            currentTranscriptionInputDuration = audioDuration(at: url)
        }
        
        // Copy and convert file to WAV format for runtime helper compatibility
        let tempWavURL = recordingsDirectory.appendingPathComponent("upload_\(Date().timeIntervalSince1970).wav")
        
        do {
            // Convert audio to WAV format (16kHz, mono, 16-bit) for consistent helper input.
            setTranscriptionProgress(0.08, status: "Converting audio…")
            if let convertedURL = try await convertToWav(source: url, destination: tempWavURL) {
                print("VoiceTranscribe: Converted audio to WAV: \(convertedURL.path)")
            } else {
                // Fallback: just copy the file directly
                try FileManager.default.copyItem(at: url, to: tempWavURL)
                print("VoiceTranscribe: Copied audio file directly: \(tempWavURL.path)")
            }
        } catch {
            print("VoiceTranscribe: Failed to prepare audio file: \(error)")
            finishProcessingSession()
            state = .error("Failed to process audio file: \(error.localizedDescription)")
            return
        }

        do {
            setTranscriptionProgress(0.2, status: "Transcribing audio…")
            print("VoiceTranscribe: Starting transcription of \(tempWavURL.path)")
            let result = try await runRuntimeCommand("transcribe", arguments: [
                "model": selectedModel.rawValue,
                "language": selectedLanguage,
                "audioPath": tempWavURL.path
            ])
            try Task.checkCancellation()
            print("VoiceTranscribe: Runtime helper transcription completed")
            setTranscriptionProgress(0.98, status: "Finalizing transcript…")

            let text = (result["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                transcriptionResult = text
                print("VoiceTranscribe: File transcription complete - \(transcriptionResult.count) chars")
                presentTranscriptionResult()
                finishProcessingSession()
                state = .idle
            } else {
                print("VoiceTranscribe: No transcription results returned")
                transcriptionResult = ""
                finishProcessingSession()
                state = .idle
            }
            
        } catch is CancellationError {
            finishProcessingSession()
            state = .idle
        } catch {
            print("VoiceTranscribe: File transcription error: \(error)")
            finishProcessingSession()
            state = .error("Transcription failed: \(error.localizedDescription)")
        }
        
        // Clean up temp file (NOT the original)
        try? FileManager.default.removeItem(at: tempWavURL)
    }

    private func presentTranscriptionResult() {
        guard !transcriptionResult.isEmpty else { return }

        let shouldAutoCopy = UserDefaults.standard.preference(
            AppPreferenceKey.voiceTranscribeAutoCopyResult,
            default: PreferenceDefault.voiceTranscribeAutoCopyResult
        )

        if shouldAutoCopy {
            VoiceTranscriptionResultController.shared.hideWindow()
            TextCopyFeedback.copyTranscriptionText(transcriptionResult)
            discardRecording()
        } else {
            VoiceTranscriptionResultController.shared.show(with: transcriptionResult)
        }
    }
    
    /// Convert audio file to WAV format for runtime helper input (16kHz, mono, 16-bit PCM)
    private func convertToWav(source: URL, destination: URL) async throws -> URL? {
        let asset = AVAsset(url: source)
        
        // Check if file has audio track
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw NSError(domain: "VoiceTranscribe", code: 1, userInfo: [NSLocalizedDescriptionKey: "No audio track found in file"])
        }
        
        // Create export session
        guard let _ = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            // Can't convert, just copy
            return nil
        }
        
        // For WAV, we need a different approach - use AVAudioFile
        let sourceFile = try AVAudioFile(forReading: source)
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
        
        guard let converter = AVAudioConverter(from: sourceFile.processingFormat, to: format) else {
            return nil
        }
        
        let outputFile = try AVAudioFile(forWriting: destination, settings: format.settings)
        
        let bufferCapacity: AVAudioFrameCount = 4096
        nonisolated(unsafe) let inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFile.processingFormat, frameCapacity: bufferCapacity)!
        let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferCapacity)!
        
        while true {
            do {
                try sourceFile.read(into: inputBuffer)
            } catch {
                break // End of file
            }
            
            if inputBuffer.frameLength == 0 {
                break
            }
            
            var error: NSError?
            converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return inputBuffer
            }
            
            if let error = error {
                throw error
            }
            
            try outputFile.write(from: outputBuffer)
        }
        
        return destination
    }

    private func beginProcessingSession(inputDuration: TimeInterval, initialStatus: String) {
        state = .processing
        processingStartedAt = Date()
        processingElapsed = 0
        currentTranscriptionInputDuration = max(0, inputDuration)
        transcriptionStatus = initialStatus
        transcriptionProgress = 0.01
        lastObservedProgressAt = Date()

        processingTimer?.invalidate()
        processingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard case .processing = self.state else { return }

                if let startedAt = self.processingStartedAt {
                    self.processingElapsed = Date().timeIntervalSince(startedAt)
                }

                if let lastProgress = self.lastObservedProgressAt,
                   Date().timeIntervalSince(lastProgress) > 8,
                   self.transcriptionProgress < 0.92 {
                    self.transcriptionProgress = min(0.92, self.transcriptionProgress + 0.003)
                    if self.processingElapsed > 12 {
                        if self.selectedModel == .large && self.currentTranscriptionInputDuration < 15 {
                            self.transcriptionStatus = "First run with Large model can take 1-2 minutes while macOS optimizes it."
                        } else {
                            self.transcriptionStatus = "Still transcribing. Large recordings can take several minutes."
                        }
                    }
                }
            }
        }
        if let processingTimer {
            RunLoop.main.add(processingTimer, forMode: .common)
        }
    }

    private func finishProcessingSession() {
        processingTimer?.invalidate()
        processingTimer = nil
        processingStartedAt = nil
        lastObservedProgressAt = nil
        transcriptionProgress = 0
        processingElapsed = 0
        currentTranscriptionInputDuration = 0
        transcriptionStatus = ""
    }

    private func setTranscriptionProgress(_ value: Double, status: String? = nil) {
        transcriptionProgress = min(max(value, 0), 1)
        if let status {
            transcriptionStatus = status
        }
        lastObservedProgressAt = Date()
    }

    private func clearTranscriptionTaskReference() {
        transcriptionTask = nil
    }

    private func audioDuration(at url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0 else { return 0 }
        return Double(file.length) / sampleRate
    }
    
    private func checkModelStatus() {
        Task { @MainActor in
            await refreshModelStatusFromRuntime()
        }
    }

    private func bindRuntimeState() {
        runtimeManager.$state
            .sink { [weak self] state in
                guard let self else { return }

                switch state {
                case .installed, .updateAvailable:
                    Task { @MainActor [weak self] in
                        await self?.refreshModelStatusFromRuntime()
                    }
                case .notInstalled:
                    self.isModelDownloaded = false
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }
    
    private func loadPreferences() {
        // If extension is disabled, don't load any preferences
        guard !ExtensionType.voiceTranscribe.isRemoved else {
            isMenuBarEnabled = false
            VoiceTranscribeMenuBar.shared.setVisible(false)
            return
        }
        
        if let modelRaw = UserDefaults.standard.string(forKey: "voiceTranscribeModel"),
           let model = WhisperModel(rawValue: modelRaw) {
            selectedModel = model
        }
        isModelDownloaded = UserDefaults.standard.bool(forKey: "voiceTranscribeModelDownloaded_\(selectedModel.rawValue)")
        if let lang = UserDefaults.standard.string(forKey: "voiceTranscribeLanguage") {
            selectedLanguage = lang
        }
        isMenuBarEnabled = UserDefaults.standard.bool(forKey: "voiceTranscribeMenuBarEnabled")
        
        // Explicitly set menu bar visibility (didSet may not fire on initial load)
        VoiceTranscribeMenuBar.shared.setVisible(isMenuBarEnabled)
    }
    
    private func savePreferences() {
        UserDefaults.standard.set(selectedModel.rawValue, forKey: "voiceTranscribeModel")
        UserDefaults.standard.set(selectedLanguage, forKey: "voiceTranscribeLanguage")
        // Save download state per model
        if isModelDownloaded {
            UserDefaults.standard.set(true, forKey: "voiceTranscribeModelDownloaded_\(selectedModel.rawValue)")
        }
    }

    private func warmModelInBackgroundIfNeeded(_ model: WhisperModel) {
        guard runtimeManager.isInstalled else { return }
        guard isModelDownloaded else { return }
        let warmKey = "voiceTranscribeModelWarmed_\(model.rawValue)"
        guard !UserDefaults.standard.bool(forKey: warmKey) else { return }
        guard !warmingModels.contains(model) else { return }

        warmingModels.insert(model)
        Task { [weak self] in
            guard let self else { return }
            defer { self.warmingModels.remove(model) }

            do {
                _ = try await self.runRuntimeCommand("warmModel", arguments: ["model": model.rawValue])
                UserDefaults.standard.set(true, forKey: warmKey)
                print("VoiceTranscribe: Warmed model \(model.rawValue) in background")
            } catch {
                print("VoiceTranscribe: Background warmup failed for \(model.rawValue): \(error)")
            }
        }
    }
}

// MARK: - Duration Formatting

extension VoiceTranscribeManager {
    var formattedDuration: String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        let tenths = Int((recordingDuration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }
}

// MARK: - Extension Removal Cleanup

extension VoiceTranscribeManager {
    /// Clean up all Voice Transcribe resources when extension is removed
    /// Deletes downloaded runtime/model resources and resets all state
    func cleanup() {
        // Stop any active recording
        if state == .recording {
            stopRecording()
        }

        transcriptionTask?.cancel()
        transcriptionTask = nil
        finishProcessingSession()
        
        // Cancel any ongoing download
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        downloadProgress = 0
        
        // Reset state
        isModelDownloaded = false
        transcriptionResult = ""
        
        // Clear preferences
        UserDefaults.standard.removeObject(forKey: "voiceTranscribeModel")
        UserDefaults.standard.removeObject(forKey: "voiceTranscribeLanguage")
        for model in WhisperModel.allCases {
            UserDefaults.standard.removeObject(forKey: "voiceTranscribeModelDownloaded_\(model.rawValue)")
            UserDefaults.standard.removeObject(forKey: "voiceTranscribeModelWarmed_\(model.rawValue)")
        }
        
        // Hide menu bar item
        VoiceTranscribeMenuBar.shared.setVisible(false)
        isMenuBarEnabled = false

        Task {
            _ = try? await runRuntimeCommand("deleteAllModels")
            await VoiceTranscribeRuntimeManager.shared.uninstallRuntime()
        }
        
        print("[VoiceTranscribe] Cleanup complete")
    }
}

// MARK: - Keyboard Shortcuts

extension VoiceTranscribeManager {
    private static let disallowedUnmodifiedShortcutKeyCodes: Set<Int> = [
        96,  // F5 (Dictation / Keyboard brightness down)
        97,  // F6 (Do Not Disturb / Keyboard brightness up)
        98,  // F7 (Previous track)
        99,  // F3 (Mission Control)
        100, // F8 (Play/Pause)
        101, // F9 (Next track)
        103, // F11 (Volume down)
        109, // F10 (Mute)
        111, // F12 (Volume up)
        118, // F4 (Spotlight)
        120, // F2 (Brightness up)
        122  // F1 (Brightness down)
    ]

    private static func sanitizeShortcut(_ shortcut: SavedShortcut?) -> SavedShortcut? {
        guard let shortcut else { return nil }
        let flags = NSEvent.ModifierFlags(rawValue: shortcut.modifiers)
            .intersection([.command, .shift, .option, .control, .function])

        // Unmodified top-row hardware/media keys still trigger system actions (OSD/sound/volume),
        // so they are not safe global shortcuts for recording toggles.
        if flags.isEmpty && disallowedUnmodifiedShortcutKeyCodes.contains(shortcut.keyCode) {
            print("[VoiceTranscribe] Ignoring unsupported unmodified media key shortcut: \(shortcut.keyCode)")
            return nil
        }

        return SavedShortcut(keyCode: shortcut.keyCode, modifiers: flags.rawValue)
    }

    /// Load shortcut preferences from UserDefaults
    func loadShortcutPreferences() {
        if let data = UserDefaults.standard.data(forKey: "voiceTranscribeQuickRecordShortcut"),
           let shortcut = try? JSONDecoder().decode(SavedShortcut.self, from: data) {
            quickRecordShortcut = Self.sanitizeShortcut(shortcut)
        }
        if let data = UserDefaults.standard.data(forKey: "voiceTranscribeInvisiRecordShortcut"),
           let shortcut = try? JSONDecoder().decode(SavedShortcut.self, from: data) {
            invisiRecordShortcut = Self.sanitizeShortcut(shortcut)
        }
        
        // Start monitoring if we have any shortcuts
        if quickRecordShortcut != nil || invisiRecordShortcut != nil {
            startGlobalKeyMonitoring()
        }
    }
    
    /// Save shortcut preferences to UserDefaults
    func saveShortcutPreferences() {
        if let shortcut = quickRecordShortcut,
           let data = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(data, forKey: "voiceTranscribeQuickRecordShortcut")
        } else {
            UserDefaults.standard.removeObject(forKey: "voiceTranscribeQuickRecordShortcut")
        }
        
        if let shortcut = invisiRecordShortcut,
           let data = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(data, forKey: "voiceTranscribeInvisiRecordShortcut")
        } else {
            UserDefaults.standard.removeObject(forKey: "voiceTranscribeInvisiRecordShortcut")
        }
        
        // Update monitoring based on shortcut availability
        if quickRecordShortcut != nil || invisiRecordShortcut != nil {
            startGlobalKeyMonitoring()
        } else {
            stopGlobalKeyMonitoring()
        }
    }
    
    /// Start global keyboard monitoring for shortcuts
    func startGlobalKeyMonitoring() {
        // Register Quick Record shortcut
        if let shortcut = quickRecordShortcut, quickRecordHotkey == nil {
            quickRecordHotkey = GlobalHotKey(
                keyCode: shortcut.keyCode,
                modifiers: shortcut.modifiers,
                enableIOHIDFallback: false
            ) { [weak self] in
                guard let self = self else { return }
                guard !ExtensionType.voiceTranscribe.isRemoved else { return }
                guard self.runtimeManager.isInstalled else { return }
                guard self.isModelDownloaded else { return }
                
                print("[VoiceTranscribe] ✅ Quick Record triggered via GlobalHotKey")
                self.triggerQuickRecord()
            }
        }
        
        // Register Invisi-Record shortcut
        if let shortcut = invisiRecordShortcut, invisiRecordHotkey == nil {
            invisiRecordHotkey = GlobalHotKey(
                keyCode: shortcut.keyCode,
                modifiers: shortcut.modifiers,
                enableIOHIDFallback: false
            ) { [weak self] in
                guard let self = self else { return }
                guard !ExtensionType.voiceTranscribe.isRemoved else { return }
                guard self.runtimeManager.isInstalled else { return }
                guard self.isModelDownloaded else { return }
                
                print("[VoiceTranscribe] ✅ Invisi-Record triggered via GlobalHotKey")
                self.triggerInvisiRecord()
            }
        }
        
        print("[VoiceTranscribe] Global key monitoring started (using GlobalHotKey/Carbon)")
    }
    
    /// Stop global keyboard monitoring
    func stopGlobalKeyMonitoring() {
        quickRecordHotkey = nil   // GlobalHotKey deinit handles unregistration
        invisiRecordHotkey = nil
        print("[VoiceTranscribe] Global key monitoring stopped")
    }
    
    /// Handle global key events (unused with GlobalHotKey, kept for reference)
    private func handleGlobalKeyEvent(_ event: NSEvent) {
        // No longer used - GlobalHotKey handles matching internally
    }
    
    /// Trigger quick record via shortcut (shows recording window)
    private func triggerQuickRecord() {
        if state == .recording {
            VoiceRecordingWindowController.shared.stopRecordingAndTranscribe()
        } else if state == .idle {
            VoiceRecordingWindowController.shared.showAndStartRecording()
        }
    }
    
    /// Trigger invisi-record via shortcut (no window)
    private func triggerInvisiRecord() {
        if state == .recording {
            stopRecording()
            VoiceRecordingWindowController.shared.showTranscribingProgress()
        } else if state == .idle {
            startRecording()
        }
    }
    
    /// Set shortcut for a recording mode
    func setShortcut(_ shortcut: SavedShortcut?, for mode: VoiceRecordingMode) {
        let sanitized = Self.sanitizeShortcut(shortcut)
        switch mode {
        case .quick:
            quickRecordShortcut = sanitized
        case .invisi:
            invisiRecordShortcut = sanitized
        }
    }
    
    /// Remove shortcut for a recording mode
    func removeShortcut(for mode: VoiceRecordingMode) {
        setShortcut(nil, for: mode)
    }
}

/// Recording modes for Voice Transcribe
enum VoiceRecordingMode: String, CaseIterable, Identifiable {
    case quick = "quick"
    case invisi = "invisi"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .quick: return "Quick Record"
        case .invisi: return "Invisi-Record"
        }
    }
    
    var icon: String {
        switch self {
        case .quick: return "record.circle"
        case .invisi: return "eye.slash.circle"
        }
    }
    
    var description: String {
        switch self {
        case .quick: return "Record with visible window"
        case .invisi: return "Background recording (no window)"
        }
    }
}
