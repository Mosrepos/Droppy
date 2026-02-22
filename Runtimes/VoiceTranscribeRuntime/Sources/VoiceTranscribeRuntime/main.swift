import Foundation
import WhisperKit

private struct RuntimeState: Codable {
    var installedModels: [String: String]

    static let empty = RuntimeState(installedModels: [:])
}

private enum RuntimeError: LocalizedError {
    case missingAction
    case invalidRequest
    case missingArgument(String)
    case modelNotInstalled(String)
    case invalidAudioPath(String)

    var errorDescription: String? {
        switch self {
        case .missingAction:
            return "Missing action in request."
        case .invalidRequest:
            return "Invalid JSON-RPC request."
        case .missingArgument(let key):
            return "Missing argument: \(key)."
        case .modelNotInstalled(let model):
            return "Model is not installed: \(model)."
        case .invalidAudioPath(let path):
            return "Audio file was not found: \(path)."
        }
    }
}

@MainActor
@main
struct VoiceTranscribeRuntime {
    static func main() async {
        do {
            guard CommandLine.arguments.contains("--json-rpc") else {
                throw RuntimeError.invalidRequest
            }

            let requestData = FileHandle.standardInput.readDataToEndOfFile()
            guard !requestData.isEmpty else {
                throw RuntimeError.invalidRequest
            }

            guard let raw = try JSONSerialization.jsonObject(with: requestData) as? [String: Any] else {
                throw RuntimeError.invalidRequest
            }

            guard let action = raw["action"] as? String, !action.isEmpty else {
                throw RuntimeError.missingAction
            }

            let arguments = raw["arguments"] as? [String: Any] ?? [:]
            let payload = try await handle(action: action, arguments: arguments)
            writeJSON(["ok": true, "payload": payload], to: .standardOutput)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            writeJSON(["ok": false, "error": message], to: .standardOutput)
            exit(0)
        }
    }

    private static var runtimeRoot: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)

        return appSupport
            .appendingPathComponent("Droppy", isDirectory: true)
            .appendingPathComponent("Extensions", isDirectory: true)
            .appendingPathComponent("voiceTranscribe", isDirectory: true)
    }

    private static var modelsRoot: URL {
        runtimeRoot.appendingPathComponent("models", isDirectory: true)
    }

    private static var stateFileURL: URL {
        runtimeRoot.appendingPathComponent("runtime-state.json", isDirectory: false)
    }

    private static func handle(action: String, arguments: [String: Any]) async throws -> [String: Any] {
        try ensureRuntimeDirectories()

        switch action {
        case "status":
            return try status(arguments: arguments)

        case "installModel":
            let model = try requireString(arguments: arguments, key: "model")
            return try await installModel(model)

        case "transcribe":
            let model = try requireString(arguments: arguments, key: "model")
            let audioPath = try requireString(arguments: arguments, key: "audioPath")
            let language = (arguments["language"] as? String) ?? "auto"
            return try await transcribe(model: model, audioPath: audioPath, language: language)

        case "warmModel":
            let model = try requireString(arguments: arguments, key: "model")
            return try await warmModel(model)

        case "deleteModel":
            let model = try requireString(arguments: arguments, key: "model")
            return try deleteModel(model)

        case "deleteAllModels":
            return try deleteAllModels()

        default:
            throw RuntimeError.invalidRequest
        }
    }

    private static func status(arguments: [String: Any]) throws -> [String: Any] {
        var state = loadState()
        pruneMissingModels(from: &state)

        if let model = arguments["model"] as? String, !model.isEmpty {
            let installed = isInstalled(model: model, in: state)
            return [
                "model": model,
                "installed": installed,
                "installedModels": state.installedModels.keys.sorted()
            ]
        }

        return [
            "installedModels": state.installedModels.keys.sorted()
        ]
    }

    private static func installModel(_ model: String) async throws -> [String: Any] {
        var state = loadState()
        pruneMissingModels(from: &state)

        if let existingPath = state.installedModels[model],
           FileManager.default.fileExists(atPath: existingPath) {
            return [
                "model": model,
                "installed": true,
                "modelPath": existingPath
            ]
        }

        let whisper = try await WhisperKit(
            model: model,
            downloadBase: modelsRoot,
            verbose: false,
            logLevel: .none,
            prewarm: false,
            load: false,
            download: true
        )

        guard let modelFolder = whisper.modelFolder?.path,
              FileManager.default.fileExists(atPath: modelFolder) else {
            throw RuntimeError.modelNotInstalled(model)
        }

        state.installedModels[model] = modelFolder
        saveState(state)

        return [
            "model": model,
            "installed": true,
            "modelPath": modelFolder
        ]
    }

    private static func transcribe(model: String, audioPath: String, language: String) async throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: audioPath) else {
            throw RuntimeError.invalidAudioPath(audioPath)
        }

        var state = loadState()
        pruneMissingModels(from: &state)

        guard let modelFolder = state.installedModels[model],
              FileManager.default.fileExists(atPath: modelFolder) else {
            throw RuntimeError.modelNotInstalled(model)
        }

        let whisper = try await WhisperKit(
            model: model,
            modelFolder: modelFolder,
            verbose: false,
            logLevel: .none,
            prewarm: false,
            load: false,
            download: false
        )

        try await whisper.loadModels()

        var options = DecodingOptions()
        if language != "auto" {
            options.language = language
        }

        let results = try await whisper.transcribe(audioPath: audioPath, decodeOptions: options)
        let text = results.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return [
            "text": text
        ]
    }

    private static func warmModel(_ model: String) async throws -> [String: Any] {
        var state = loadState()
        pruneMissingModels(from: &state)

        guard let modelFolder = state.installedModels[model],
              FileManager.default.fileExists(atPath: modelFolder) else {
            throw RuntimeError.modelNotInstalled(model)
        }

        let whisper = try await WhisperKit(
            model: model,
            modelFolder: modelFolder,
            verbose: false,
            logLevel: .none,
            prewarm: false,
            load: false,
            download: false
        )

        try await whisper.loadModels()
        try await whisper.prewarmModels()

        return [
            "model": model,
            "warmed": true
        ]
    }

    private static func deleteModel(_ model: String) throws -> [String: Any] {
        var state = loadState()

        if let path = state.installedModels[model], FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(atPath: path)
        }

        state.installedModels.removeValue(forKey: model)
        saveState(state)

        return [
            "model": model,
            "deleted": true
        ]
    }

    private static func deleteAllModels() throws -> [String: Any] {
        let state = loadState()

        for path in state.installedModels.values where FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(atPath: path)
        }

        if FileManager.default.fileExists(atPath: modelsRoot.path) {
            try? FileManager.default.removeItem(at: modelsRoot)
        }

        try ensureRuntimeDirectories()
        saveState(.empty)

        return [
            "deletedAll": true
        ]
    }

    private static func requireString(arguments: [String: Any], key: String) throws -> String {
        guard let value = arguments[key] as? String, !value.isEmpty else {
            throw RuntimeError.missingArgument(key)
        }
        return value
    }

    private static func isInstalled(model: String, in state: RuntimeState) -> Bool {
        guard let path = state.installedModels[model] else {
            return false
        }
        return FileManager.default.fileExists(atPath: path)
    }

    private static func ensureRuntimeDirectories() throws {
        try FileManager.default.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
    }

    private static func loadState() -> RuntimeState {
        guard let data = try? Data(contentsOf: stateFileURL) else {
            return .empty
        }

        return (try? JSONDecoder().decode(RuntimeState.self, from: data)) ?? .empty
    }

    private static func saveState(_ state: RuntimeState) {
        guard let data = try? JSONEncoder().encode(state) else {
            return
        }
        try? data.write(to: stateFileURL, options: .atomic)
    }

    private static func pruneMissingModels(from state: inout RuntimeState) {
        state.installedModels = state.installedModels.filter { _, path in
            FileManager.default.fileExists(atPath: path)
        }
        saveState(state)
    }

    private static func writeJSON(_ object: [String: Any], to handle: FileHandle) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: []) else {
            return
        }

        handle.write(data)
    }
}
