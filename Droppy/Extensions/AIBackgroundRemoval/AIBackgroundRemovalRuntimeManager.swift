import Foundation
import Combine
import CryptoKit

private nonisolated final class AIBackgroundRuntimeOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func outputString() -> String {
        lock.lock()
        let snapshot = data
        lock.unlock()
        return String(data: snapshot, encoding: .utf8) ?? ""
    }
}

enum AIBackgroundRuntimeInstallState: Equatable {
    case checking
    case notInstalled
    case installing(progress: Double)
    case installed(version: String)
    case updateAvailable(currentVersion: String, latestVersion: String)
    case failed(String)
}

private struct AIBackgroundRuntimeManifest: Codable {
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

enum AIBackgroundRuntimeIPCError: LocalizedError {
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

@MainActor
final class AIBackgroundRemovalRuntimeManager: ObservableObject {
    static let shared = AIBackgroundRemovalRuntimeManager()

    @Published private(set) var state: AIBackgroundRuntimeInstallState = .checking
    @Published private(set) var installedVersion: String?
    @Published private(set) var latestVersion: String?
    @Published private(set) var lastError: String?

    private let installedVersionKey = "aiBackgroundRemovalRuntimeInstalledVersion"
    private let installedExecutableKey = "aiBackgroundRemovalRuntimeInstalledExecutablePath"
    private let latestVersionKey = "aiBackgroundRemovalRuntimeLatestVersion"
    private let manifestBaseURLString = "https://github.com/iordv/Droppy/releases/download/ai-bg-runtime/ai-bg-runtime-manifest.txt"
    private let expectedExtensionID = "aiBackgroundRemoval"
    private let expectedProtocolVersion = 1

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

            guard artifactForCurrentArchitecture(from: manifest) != nil else {
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
                state = .notInstalled
            }
        } catch {
            if let installedVersion = installedVersion, executableURL != nil {
                state = .installed(version: installedVersion)
            } else {
                let message = friendlyErrorMessage(error)
                state = .failed(message)
                lastError = message
            }
        }
    }

    func installOrUpdateRuntime() async throws {
        guard !isInstalling else { return }

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
                .appendingPathComponent("DroppyAIBgRuntimeInstall-\(UUID().uuidString)", isDirectory: true)
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
            NotificationCenter.default.post(name: .extensionStateChanged, object: ExtensionType.aiBackgroundRemoval)
        } catch {
            let message = friendlyErrorMessage(error)
            state = .failed(message)
            lastError = message
            throw error
        }
    }

    func uninstallRuntime() async throws {
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
            NotificationCenter.default.post(name: .extensionStateChanged, object: ExtensionType.aiBackgroundRemoval)
        } catch {
            let message = "Failed to remove runtime files: \(error.localizedDescription)"
            state = .failed(message)
            lastError = message
            throw error
        }
    }

    func runCommand(_ action: String, arguments: [String: Any] = [:]) async throws -> [String: Any] {
        guard isInstalled else {
            throw AIBackgroundRuntimeIPCError.runtimeNotInstalled
        }
        guard let executableURL = executableURL else {
            throw AIBackgroundRuntimeIPCError.executableMissing
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

            let stdoutBuffer = AIBackgroundRuntimeOutputBuffer()
            let stderrBuffer = AIBackgroundRuntimeOutputBuffer()

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

                let outText = stdoutBuffer.outputString()
                let errText = stderrBuffer.outputString()
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard proc.terminationStatus == 0 else {
                    let message = errText.isEmpty ? "Runtime command '\(action)' failed with exit \(proc.terminationStatus)." : errText
                    continuation.resume(throwing: AIBackgroundRuntimeIPCError.processFailed(message))
                    return
                }

                guard let outData = outText.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: outData, options: []),
                      let dict = json as? [String: Any] else {
                    let preview = [outText.prefix(240), errText.prefix(240)]
                        .map(String.init)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .joined(separator: " | ")
                    let reason = preview.isEmpty ? "Runtime returned an invalid response." : "Runtime returned an invalid response: \(preview)"
                    continuation.resume(throwing: AIBackgroundRuntimeIPCError.invalidResponse(reason))
                    return
                }

                if let ok = dict["ok"] as? Bool, ok == false {
                    let message = (dict["error"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let resolvedMessage = message.flatMap { $0.isEmpty ? nil : $0 } ?? "Runtime command failed."
                    continuation.resume(throwing: AIBackgroundRuntimeIPCError.helperError(resolvedMessage))
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

    private func validateManifest(_ manifest: AIBackgroundRuntimeManifest) throws {
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

    private func fetchManifest(from url: URL) async throws -> AIBackgroundRuntimeManifest {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw RuntimeInstallError.network("Manifest response was invalid.")
        }
        guard (200...299).contains(http.statusCode) else {
            throw RuntimeInstallError.network("Manifest request failed with HTTP \(http.statusCode).")
        }
        do {
            return try JSONDecoder().decode(AIBackgroundRuntimeManifest.self, from: data)
        } catch {
            throw RuntimeInstallError.invalidManifest("Manifest could not be decoded.")
        }
    }

    private func artifactForCurrentArchitecture(from manifest: AIBackgroundRuntimeManifest) -> AIBackgroundRuntimeManifest.Artifact? {
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
            .appendingPathComponent("aiBackgroundRemoval", isDirectory: true)
            .appendingPathComponent("runtime", isDirectory: true)
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
