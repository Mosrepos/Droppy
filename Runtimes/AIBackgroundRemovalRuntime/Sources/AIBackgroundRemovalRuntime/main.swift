import Foundation
import Dispatch

private enum RuntimeError: LocalizedError {
    case missingAction
    case invalidRequest
    case missingArgument(String)
    case missingModelFile
    case invalidModelFile

    var errorDescription: String? {
        switch self {
        case .missingAction:
            return "Missing action in request."
        case .invalidRequest:
            return "Invalid JSON-RPC request."
        case .missingArgument(let key):
            return "Missing argument: \(key)."
        case .missingModelFile:
            return "Model file is missing."
        case .invalidModelFile:
            return "Model file is invalid."
        }
    }
}

private enum AIBackgroundRemovalRuntime {
    static func run() async {
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
        }
    }

    private static func handle(action: String, arguments: [String: Any]) async throws -> [String: Any] {
        switch action {
        case "status":
            return ["ready": true]

        case "validateRuntime":
            let modelPath = try requireString(arguments: arguments, key: "modelPath")
            try validateModelFile(at: modelPath)
            return ["validated": true]

        case "removeBackground":
            let imagePath = try requireString(arguments: arguments, key: "imagePath")
            let modelPath = try requireString(arguments: arguments, key: "modelPath")
            let outputPath = try requireString(arguments: arguments, key: "outputPath")

            let inputURL = URL(fileURLWithPath: imagePath, isDirectory: false)
            let outputURL = URL(fileURLWithPath: outputPath, isDirectory: false)
            let outputData = try await BiRefNetEngine.shared.removeBackground(imageURL: inputURL, modelPath: modelPath)
            try outputData.write(to: outputURL, options: .atomic)

            return [
                "outputPath": outputURL.path,
                "bytes": outputData.count
            ]

        default:
            throw RuntimeError.invalidRequest
        }
    }

    private static func requireString(arguments: [String: Any], key: String) throws -> String {
        guard let value = arguments[key] as? String, !value.isEmpty else {
            throw RuntimeError.missingArgument(key)
        }
        return value
    }

    private static func validateModelFile(at path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw RuntimeError.missingModelFile
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        // Reject obviously invalid/truncated files while keeping validation deterministic.
        guard size > 256 * 1024 * 1024 else {
            throw RuntimeError.invalidModelFile
        }
    }

    private static func writeJSON(_ object: [String: Any], to handle: FileHandle) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: []) else {
            return
        }

        handle.write(data)
    }
}

Task.detached {
    await AIBackgroundRemovalRuntime.run()
    exit(0)
}

dispatchMain()
