import Foundation
import CoreGraphics
@preconcurrency import OnnxRuntimeBindings

enum BiRefNetEngineError: LocalizedError {
    case runtimeUnavailable(String)
    case modelMissing
    case modelInvalid
    case inferenceFailed(String)

    var errorDescription: String? {
        switch self {
        case .runtimeUnavailable(let message):
            return message
        case .modelMissing:
            return "BiRefNet model file is missing."
        case .modelInvalid:
            return "BiRefNet model file is invalid."
        case .inferenceFailed(let message):
            return message
        }
    }
}

actor BiRefNetEngine {
    static let shared = BiRefNetEngine()

    private var env: ORTEnv?
    private var session: ORTSession?
    private var sessionModelPath: String?
    private var inputName: String?
    private var outputName: String?

    private init() {
        env = nil
    }

    func resetSession() {
        session = nil
        sessionModelPath = nil
        inputName = nil
        outputName = nil
        env = nil
    }

    func validateRuntime(modelPath: String) async throws {
        defer { resetSession() }
        try autoreleasepool {
            let warmupImage = try makeWarmupImage(size: 64)
            _ = try runInference(on: warmupImage, modelPath: modelPath)
        }
    }

    func removeBackground(imageURL: URL, modelPath: String) async throws -> Data {
        defer { resetSession() }
        return try autoreleasepool {
            let prepared = try BiRefNetPrePostProcessor.prepareInput(from: imageURL)
            let output = try runSession(prepared: prepared, modelPath: modelPath)
            return try BiRefNetPrePostProcessor.outputPNGData(from: output, originalImage: prepared.originalImage)
        }
    }

    private func runInference(on image: CGImage, modelPath: String) throws -> ORTValue {
        let prepared = try BiRefNetPrePostProcessor.prepareInput(from: image)
        return try runSession(prepared: prepared, modelPath: modelPath)
    }

    private func runSession(prepared: BiRefNetPreparedInput, modelPath: String) throws -> ORTValue {
        try ensureSession(modelPath: modelPath)

        guard let session,
              let inputName,
              let outputName else {
            throw BiRefNetEngineError.runtimeUnavailable("ONNX runtime session is unavailable.")
        }

        do {
            let inputTensorData = NSMutableData(data: prepared.tensorData)
            let inputValue = try ORTValue(
                tensorData: inputTensorData,
                elementType: .float,
                shape: prepared.shape
            )
            let runOptions = try makeRunOptions()

            let outputs = try session.run(
                withInputs: [inputName: inputValue],
                outputNames: Set([outputName]),
                runOptions: runOptions
            )

            guard let outputValue = outputs[outputName] else {
                throw BiRefNetEngineError.inferenceFailed("Model did not return expected output tensor.")
            }

            return outputValue
        } catch {
            throw BiRefNetEngineError.inferenceFailed("BiRefNet inference failed: \(error.localizedDescription)")
        }
    }

    private func ensureSession(modelPath: String) throws {
        let env = try ensureEnv()

        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw BiRefNetEngineError.modelMissing
        }

        if session != nil, sessionModelPath == modelPath {
            return
        }

        do {
            let options = try ORTSessionOptions()
            // Keep memory usage predictable on both Intel and Apple Silicon.
            try options.setGraphOptimizationLevel(.basic)
            try options.setIntraOpNumThreads(1)
            // Avoid large persistent weight prepack caches for full-model runs.
            try options.addConfigEntry(withKey: "session.disable_prepacking", value: "1")
            try options.addConfigEntry(withKey: "session.force_spinning_stop", value: "1")
            try options.addConfigEntry(withKey: "session.intra_op.allow_spinning", value: "0")
            // CoreML/ANE compilation for the full BiRefNet model is not stable across devices.
            // Keep the runtime deterministic by staying on ORT's default CPU execution path.

            let session = try ORTSession(env: env, modelPath: modelPath, sessionOptions: options)
            guard let inputName = try session.inputNames().first else {
                throw BiRefNetEngineError.modelInvalid
            }

            let outputNames = try session.outputNames()
            guard !outputNames.isEmpty else {
                throw BiRefNetEngineError.modelInvalid
            }
            let outputName = choosePrimaryOutputName(from: outputNames)

            self.session = session
            self.sessionModelPath = modelPath
            self.inputName = inputName
            self.outputName = outputName
        } catch {
            self.session = nil
            self.sessionModelPath = nil
            self.inputName = nil
            self.outputName = nil
            throw BiRefNetEngineError.runtimeUnavailable("Failed to initialize BiRefNet session: \(error.localizedDescription)")
        }
    }

    private func ensureEnv() throws -> ORTEnv {
        if let env {
            return env
        }

        do {
            let created = try ORTEnv(loggingLevel: .warning)
            env = created
            return created
        } catch {
            throw BiRefNetEngineError.runtimeUnavailable("Failed to initialize ONNX runtime environment.")
        }
    }

    private func makeRunOptions() throws -> ORTRunOptions {
        let runOptions = try ORTRunOptions()
        // Release temporary CPU arena allocations after each run.
        try runOptions.addConfigEntry(withKey: "memory.enable_memory_arena_shrinkage", value: "cpu:0")
        return runOptions
    }

    private func choosePrimaryOutputName(from outputNames: [String]) -> String {
        let preferredTokens = ["mask", "alpha", "pred", "output"]
        for token in preferredTokens {
            if let match = outputNames.first(where: { $0.localizedCaseInsensitiveContains(token) }) {
                return match
            }
        }
        return outputNames[0]
    }

    private func makeWarmupImage(size: Int) throws -> CGImage {
        var bytes = [UInt8](repeating: 255, count: size * size * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            .union(.byteOrder32Big)

        guard let context = CGContext(
            data: &bytes,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            throw BiRefNetEngineError.runtimeUnavailable("Failed to create model warmup image.")
        }

        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))

        guard let image = context.makeImage() else {
            throw BiRefNetEngineError.runtimeUnavailable("Failed to create model warmup image.")
        }

        return image
    }
}
