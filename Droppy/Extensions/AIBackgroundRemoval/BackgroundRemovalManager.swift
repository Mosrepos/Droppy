//
//  BackgroundRemovalManager.swift
//  Droppy
//
//  Created by Jordy Spruit on 11/01/2026.
//

import Foundation
import AppKit
import Combine

/// Manages AI-powered background removal using external BiRefNet runtime inference.
@MainActor
final class BackgroundRemovalManager: ObservableObject {
    static let shared = BackgroundRemovalManager()
    nonisolated private static let runtimeTimeoutSeconds: TimeInterval = 120
    private let runtimeManager = AIBackgroundRemovalRuntimeManager.shared

    @Published var isProcessing = false
    @Published var progress: Double = 0

    private init() {}

    // MARK: - Public API

    /// Remove background from an image file and save as PNG
    /// - Parameter url: URL of the source image
    /// - Returns: URL of the output image with transparent background (*_nobg.png)
    func removeBackground(from url: URL) async throws -> URL {
        guard !ExtensionType.aiBackgroundRemoval.isRemoved else {
            throw BackgroundRemovalError.extensionDisabled
        }

        guard AIInstallManager.shared.isInstalled else {
            throw BackgroundRemovalError.modelNotReady
        }

        isProcessing = true
        progress = 0.02
        await Task.yield()
        defer {
            isProcessing = false
            progress = 1.0
            MemoryRecoveryCoordinator.reclaimTransientMemory(forceAllocatorTrim: true)
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw BackgroundRemovalError.failedToLoadImage
        }

        progress = 0.1
        let preparedInputURL = try prepareInputImageForModel(from: url)
        defer { try? FileManager.default.removeItem(at: preparedInputURL) }

        progress = 0.16
        let inferencePulseTask = makeInferencePulseTask()
        defer { inferencePulseTask.cancel() }
        let outputData = try await removeBackgroundWithRuntime(preparedInputURL: preparedInputURL)
        progress = max(progress, 0.96)

        let baseName = url.deletingPathExtension().lastPathComponent
        let directory = preferredOutputDirectory(for: url)
        let outputURL = directory.appendingPathComponent("\(baseName)_nobg.png")
        let finalURL = generateUniqueURL(for: outputURL)

        try outputData.write(to: finalURL)
        guard FileManager.default.fileExists(atPath: finalURL.path) else {
            throw BackgroundRemovalError.failedToLoadImage
        }

        progress = 1.0
        return finalURL
    }

    private func makeInferencePulseTask() -> Task<Void, Never> {
        let startedAt = Date()
        let floor: Double = 0.16
        let ceiling: Double = 0.94
        let timeConstantSeconds: Double = 8.0

        return Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 220_000_000)
                await MainActor.run {
                    guard let self, self.isProcessing else { return }
                    let elapsed = Date().timeIntervalSince(startedAt)
                    let eased = floor + ((ceiling - floor) * (1 - exp(-elapsed / timeConstantSeconds)))
                    self.progress = min(ceiling, max(self.progress, eased))
                }
            }
        }
    }

    // MARK: - Private Helpers

    private func prepareInputImageForModel(from sourceURL: URL) throws -> URL {
        guard let image = NSImage(contentsOf: sourceURL) else {
            throw BackgroundRemovalError.unsupportedImageFormat
        }

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw BackgroundRemovalError.unsupportedImageFormat
        }

        let preparedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_bgremoval_input.png")

        do {
            try pngData.write(to: preparedURL, options: .atomic)
            return preparedURL
        } catch {
            throw BackgroundRemovalError.failedToLoadImage
        }
    }

    private func generateUniqueURL(for url: URL) -> URL {
        var finalURL = url
        var counter = 1

        let directory = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_nobg", with: "")
        let ext = url.pathExtension

        while FileManager.default.fileExists(atPath: finalURL.path) {
            let newName = "\(baseName)_nobg\(counter > 1 ? "_\(counter)" : "").\(ext)"
            finalURL = directory.appendingPathComponent(newName)
            counter += 1
        }

        return finalURL
    }

    /// When source files come from temporary drop locations, save outputs to Downloads
    /// so users can find the generated file outside Droppy's temp folders.
    private func preferredOutputDirectory(for sourceURL: URL) -> URL {
        let sourceDirectory = sourceURL.deletingLastPathComponent().standardizedFileURL
        let tempDirectory = FileManager.default.temporaryDirectory.standardizedFileURL

        if sourceDirectory.path.hasPrefix(tempDirectory.path),
           let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            return downloads
        }

        return sourceDirectory
    }

    private func removeBackgroundWithRuntime(preparedInputURL: URL) async throws -> Data {
        guard AIInstallManager.modelExists() else {
            throw BackgroundRemovalError.modelNotReady
        }

        guard AIInstallManager.modelSizeMatchesManifest() else {
            throw BackgroundRemovalError.modelCorrupt
        }

        do {
            return try await runRuntimeInferenceWithTimeout(preparedInputURL: preparedInputURL)
        } catch let error as BackgroundRemovalError {
            throw error
        } catch let error as AIBackgroundRuntimeIPCError {
            throw BackgroundRemovalError.inferenceFailed(error.localizedDescription)
        } catch {
            throw BackgroundRemovalError.inferenceFailed(error.localizedDescription)
        }
    }

    private func runRuntimeInferenceWithTimeout(preparedInputURL: URL) async throws -> Data {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_bgremoval_output.png")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let inferenceTask = Task(priority: .userInitiated) { [runtimeManager] in
            _ = try await runtimeManager.runCommand(
                "removeBackground",
                arguments: [
                    "imagePath": preparedInputURL.path,
                    "modelPath": AIInstallManager.localModelPath,
                    "outputPath": outputURL.path
                ]
            )
            return try Data(contentsOf: outputURL)
        }

        do {
            return try await withThrowingTaskGroup(of: Data.self) { group in
                group.addTask {
                    try await inferenceTask.value
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(Self.runtimeTimeoutSeconds * 1_000_000_000))
                    throw BackgroundRemovalError.processingTimedOut
                }

                guard let firstResult = try await group.next() else {
                    throw BackgroundRemovalError.inferenceFailed("No model output was produced.")
                }

                group.cancelAll()
                return firstResult
            }
        } catch BackgroundRemovalError.processingTimedOut {
            inferenceTask.cancel()
            throw BackgroundRemovalError.processingTimedOut
        } catch {
            inferenceTask.cancel()
            throw error
        }
    }
}

// MARK: - Errors

enum BackgroundRemovalError: LocalizedError {
    case failedToLoadImage
    case unsupportedImageFormat
    case modelNotReady
    case modelCorrupt
    case inferenceFailed(String)
    case processingTimedOut
    case extensionDisabled

    var errorDescription: String? {
        switch self {
        case .failedToLoadImage:
            return "Failed to load image."
        case .unsupportedImageFormat:
            return "Unsupported image format. Convert to PNG or JPEG and try again."
        case .modelNotReady:
            return "AI model is not ready. Open Extensions > AI Background Removal and run Install."
        case .modelCorrupt:
            return "AI model files are invalid. Reinstall AI Background Removal."
        case .inferenceFailed(let message):
            return "Background removal failed: \(message)"
        case .processingTimedOut:
            return "Background removal timed out. Try a smaller image or retry."
        case .extensionDisabled:
            return "AI Background Removal is disabled."
        }
    }
}
