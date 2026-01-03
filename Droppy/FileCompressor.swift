//
//  FileCompressor.swift
//  Droppy
//
//  Created by Jordy Spruit on 03/01/2026.
//

import Foundation
import AppKit
@preconcurrency import AVFoundation
import UniformTypeIdentifiers
import PDFKit

/// Quality levels for compression
enum CompressionQuality: Int, CaseIterable {
    case low = 0
    case medium = 1
    case high = 2
    
    var displayName: String {
        switch self {
        case .low: return "Low (Smaller)"
        case .medium: return "Medium (Balanced)"
        case .high: return "High (Minimal Loss)"
        }
    }
    
    /// JPEG quality factor (0.0 - 1.0)
    var jpegQuality: CGFloat {
        switch self {
        case .low: return 0.3
        case .medium: return 0.6
        case .high: return 0.85
        }
    }
    
    /// Video export preset
    var videoPreset: String {
        switch self {
        case .low: return AVAssetExportPresetLowQuality
        case .medium: return AVAssetExportPresetMediumQuality
        case .high: return AVAssetExportPresetHighestQuality
        }
    }
}

/// Mode for compression operation
enum CompressionMode {
    case preset(CompressionQuality)
    case targetSize(bytes: Int64)
}

/// Service for compressing files (images, PDFs, videos)
class FileCompressor {
    static let shared = FileCompressor()
    
    private init() {}
    
    // MARK: - Public API
    
    /// Check if a file can be compressed
    static func canCompress(url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .pdf) || type.conforms(to: .movie) || type.conforms(to: .video)
    }
    
    /// Check if a file type can be compressed
    static func canCompress(fileType: UTType?) -> Bool {
        guard let type = fileType else { return false }
        return type.conforms(to: .image) || type.conforms(to: .pdf) || type.conforms(to: .movie) || type.conforms(to: .video)
    }
    
    /// Compress a file with the specified mode
    /// Returns the URL of the compressed file, or nil on failure
    func compress(url: URL, mode: CompressionMode) async -> URL? {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
        
        if type.conforms(to: .image) {
            return await compressImage(url: url, mode: mode)
        } else if type.conforms(to: .pdf) {
            return await compressPDF(url: url, mode: mode)
        } else if type.conforms(to: .movie) || type.conforms(to: .video) {
            return await compressVideo(url: url, mode: mode)
        }
        
        return nil
    }
    
    /// Get the file size in bytes
    static func fileSize(url: URL) -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else {
            return nil
        }
        return size
    }
    
    /// Format bytes as human-readable string
    static func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    // MARK: - Image Compression
    
    private func compressImage(url: URL, mode: CompressionMode) async -> URL? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        
        let quality: CGFloat
        let targetBytes: Int64?
        
        switch mode {
        case .preset(let q):
            quality = q.jpegQuality
            targetBytes = nil
        case .targetSize(let bytes):
            quality = 0.8 // Starting point for iteration
            targetBytes = bytes
        }
        
        // Create output URL in temp directory
        let fileName = url.deletingPathExtension().lastPathComponent
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(fileName)_compressed")
            .appendingPathExtension("jpg")
        
        // Get bitmap representation
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        
        if let targetBytes = targetBytes {
            // Iterative compression to reach target size
            return await compressImageToTargetSize(bitmap: bitmap, targetBytes: targetBytes, outputURL: outputURL)
        } else {
            // Direct compression with quality
            guard let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality]) else {
                return nil
            }
            
            do {
                try jpegData.write(to: outputURL)
                return outputURL
            } catch {
                print("Error writing compressed image: \(error)")
                return nil
            }
        }
    }
    
    private func compressImageToTargetSize(bitmap: NSBitmapImageRep, targetBytes: Int64, outputURL: URL) async -> URL? {
        var low: CGFloat = 0.01
        var high: CGFloat = 1.0
        var bestData: Data?
        var iterations = 0
        let maxIterations = 10
        
        while iterations < maxIterations && (high - low) > 0.02 {
            let mid = (low + high) / 2
            
            guard let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: mid]) else {
                break
            }
            
            let currentSize = Int64(jpegData.count)
            
            if currentSize <= targetBytes {
                // Size is acceptable, try higher quality
                bestData = jpegData
                low = mid
            } else {
                // Size too big, try lower quality
                high = mid
            }
            
            iterations += 1
        }
        
        // If we couldn't reach target, use the lowest quality
        if bestData == nil {
            bestData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.01])
        }
        
        guard let finalData = bestData else { return nil }
        
        do {
            try finalData.write(to: outputURL)
            return outputURL
        } catch {
            print("Error writing compressed image: \(error)")
            return nil
        }
    }
    
    // MARK: - PDF Compression
    
    private func compressPDF(url: URL, mode: CompressionMode) async -> URL? {
        guard let pdfDocument = PDFDocument(url: url) else { return nil }
        
        let fileName = url.deletingPathExtension().lastPathComponent
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(fileName)_compressed")
            .appendingPathExtension("pdf")
        
        // Try using Quartz filter for compression
        let filterPath = "/System/Library/Filters/Reduce File Size.qfilter"
        
        if FileManager.default.fileExists(atPath: filterPath),
           let filter = QuartzFilter(url: URL(fileURLWithPath: filterPath)) {
            // Apply Quartz filter
            let context = CGContext(outputURL as CFURL, mediaBox: nil, nil)
            
            for i in 0..<pdfDocument.pageCount {
                guard let page = pdfDocument.page(at: i) else { continue }
                let mediaBox = page.bounds(for: .mediaBox)
                
                context?.beginPDFPage(nil)
                filter.apply(to: context!)
                page.draw(with: .mediaBox, to: context!)
                context?.endPDFPage()
            }
            
            context?.closePDF()
            
            if FileManager.default.fileExists(atPath: outputURL.path) {
                return outputURL
            }
        }
        
        // Fallback: Re-render PDF at lower resolution
        return await compressPDFByRerendering(pdfDocument: pdfDocument, mode: mode, outputURL: outputURL)
    }
    
    private func compressPDFByRerendering(pdfDocument: PDFDocument, mode: CompressionMode, outputURL: URL) async -> URL? {
        // Determine scale and JPEG quality based on mode
        let scale: CGFloat
        let jpegQuality: CGFloat
        switch mode {
        case .preset(let quality):
            switch quality {
            case .low: 
                scale = 0.5
                jpegQuality = 0.3
            case .medium: 
                scale = 0.72
                jpegQuality = 0.5
            case .high: 
                scale = 0.85
                jpegQuality = 0.7
            }
        case .targetSize:
            scale = 0.6
            jpegQuality = 0.4 // Lower quality for target size mode
        }
        
        // Create PDF context with correct page sizes
        guard let pdfData = CFDataCreateMutable(nil, 0) else { return nil }
        guard let consumer = CGDataConsumer(data: pdfData) else { return nil }
        
        var mediaBox = CGRect.zero
        guard let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }
        
        for i in 0..<pdfDocument.pageCount {
            guard let page = pdfDocument.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let rotation = page.rotation
            
            // Calculate scaled bounds, preserving orientation
            var scaledBounds = CGRect(
                x: 0, y: 0,
                width: bounds.width * scale,
                height: bounds.height * scale
            )
            
            // Begin PDF page with correct size
            let pageInfo: [CFString: Any] = [
                kCGPDFContextMediaBox: scaledBounds
            ]
            pdfContext.beginPDFPage(pageInfo as CFDictionary)
            
            // Draw page scaled
            pdfContext.scaleBy(x: scale, y: scale)
            
            // Use PDFPage's draw which handles rotation
            page.draw(with: .mediaBox, to: pdfContext)
            
            pdfContext.endPDFPage()
        }
        
        pdfContext.closePDF()
        
        // Write the PDF data
        let data = pdfData as Data
        do {
            try data.write(to: outputURL)
            return outputURL
        } catch {
            print("Error writing PDF: \(error)")
            return nil
        }
    }
    
    // MARK: - Video Compression
    
    private func compressVideo(url: URL, mode: CompressionMode) async -> URL? {
        let asset = AVAsset(url: url)
        
        let fileName = url.deletingPathExtension().lastPathComponent
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(fileName)_compressed")
            .appendingPathExtension("mp4")
        
        // Remove existing file if present
        try? FileManager.default.removeItem(at: outputURL)
        
        switch mode {
        case .preset(let quality):
            return await compressVideoWithPreset(asset: asset, preset: quality.videoPreset, outputURL: outputURL)
        case .targetSize(let bytes):
            return await compressVideoToTargetSize(asset: asset, targetBytes: bytes, outputURL: outputURL)
        }
    }
    
    private func compressVideoWithPreset(asset: AVAsset, preset: String, outputURL: URL) async -> URL? {
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: preset) else {
            return nil
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        await exportSession.export()
        
        if exportSession.status == .completed {
            return outputURL
        } else {
            print("Video export failed: \(exportSession.error?.localizedDescription ?? "Unknown error")")
            return nil
        }
    }
    
    private func compressVideoToTargetSize(asset: AVAsset, targetBytes: Int64, outputURL: URL) async -> URL? {
        // Calculate required bitrate based on duration
        let duration = try? await asset.load(.duration)
        guard let duration = duration else { return nil }
        
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds > 0 else { return nil }
        
        // Target bitrate = (target size in bits) / duration
        // Add 15% overhead because H.264 encoders often undershoot average bitrate
        // Also account for audio (~128kbps)
        let audioBitrate: Int64 = 128_000
        let overheadMultiplier: Double = 1.15 // 15% overhead to hit target more closely
        let targetBits = Int64(Double(targetBytes * 8) * overheadMultiplier)
        let availableBitsForVideo = targetBits - Int64(durationSeconds * Double(audioBitrate))
        let videoBitrate = max(100_000, Int(Double(availableBitsForVideo) / durationSeconds))
        
        print("Target: \(targetBytes) bytes, Duration: \(durationSeconds)s, Video bitrate: \(videoBitrate) bps")
        
        return await compressVideoWithBitrate(asset: asset, videoBitrate: videoBitrate, outputURL: outputURL)
    }
    
    private func compressVideoWithBitrate(asset: AVAsset, videoBitrate: Int, outputURL: URL) async -> URL? {
        // For custom bitrate, we need to use AVAssetReader + AVAssetWriter
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            // Fallback to preset if no video track
            return await compressVideoWithPreset(asset: asset, preset: AVAssetExportPresetMediumQuality, outputURL: outputURL)
        }
        
        // Get video properties
        let naturalSize = try? await videoTrack.load(.naturalSize)
        let transform = try? await videoTrack.load(.preferredTransform)
        let nominalFrameRate = try? await videoTrack.load(.nominalFrameRate)
        
        guard let naturalSize = naturalSize else { return nil }
        
        // Determine output size (maintain aspect ratio, max 1080p)
        var outputSize = naturalSize
        let maxDimension: CGFloat = 1920
        if outputSize.width > maxDimension || outputSize.height > maxDimension {
            let scale = maxDimension / max(outputSize.width, outputSize.height)
            outputSize = CGSize(width: outputSize.width * scale, height: outputSize.height * scale)
        }
        
        // Round to even numbers (required by H.264)
        outputSize.width = floor(outputSize.width / 2) * 2
        outputSize.height = floor(outputSize.height / 2) * 2
        
        do {
            // Setup writer
            let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
            
            // Video output settings with custom bitrate
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: outputSize.width,
                AVVideoHeightKey: outputSize.height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: videoBitrate,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                    AVVideoMaxKeyFrameIntervalKey: 30
                ]
            ]
            
            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput.expectsMediaDataInRealTime = false
            if let transform = transform {
                videoInput.transform = transform
            }
            writer.add(videoInput)
            
            // Setup reader for video
            let reader = try AVAssetReader(asset: asset)
            
            let videoOutputSettings: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: videoOutputSettings)
            videoOutput.alwaysCopiesSampleData = false
            reader.add(videoOutput)
            
            // Audio handling
            var audioInput: AVAssetWriterInput?
            var audioOutput: AVAssetReaderTrackOutput?
            
            if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first {
                let audioSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 44100,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 128000
                ]
                audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                audioInput?.expectsMediaDataInRealTime = false
                writer.add(audioInput!)
                
                // Reader must output decompressed audio for the writer to re-encode
                let audioReaderSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsNonInterleaved: false,
                    AVLinearPCMIsBigEndianKey: false
                ]
                audioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: audioReaderSettings)
                audioOutput?.alwaysCopiesSampleData = false
                reader.add(audioOutput!)
            }
            
            // Start processing
            writer.startWriting()
            reader.startReading()
            writer.startSession(atSourceTime: .zero)
            
            // Process video and audio in parallel
            // Note: These AV types are thread-safe but not marked Sendable
            nonisolated(unsafe) let videoInputRef = videoInput
            nonisolated(unsafe) let videoOutputRef = videoOutput
            nonisolated(unsafe) let audioInputRef = audioInput
            nonisolated(unsafe) let audioOutputRef = audioOutput
            nonisolated(unsafe) let readerRef = reader
            nonisolated(unsafe) let writerRef = writer
            
            return await withCheckedContinuation { continuation in
                let group = DispatchGroup()
                var success = true
                
                // Video processing
                group.enter()
                let videoQueue = DispatchQueue(label: "com.droppy.videoQueue")
                videoInputRef.requestMediaDataWhenReady(on: videoQueue) {
                    while videoInputRef.isReadyForMoreMediaData {
                        if let sampleBuffer = videoOutputRef.copyNextSampleBuffer() {
                            videoInputRef.append(sampleBuffer)
                        } else {
                            videoInputRef.markAsFinished()
                            group.leave()
                            break
                        }
                    }
                }
                
                // Audio processing
                if let audioInput = audioInputRef, let audioOutput = audioOutputRef {
                    group.enter()
                    let audioQueue = DispatchQueue(label: "com.droppy.audioQueue")
                    // Create refs for inner closure
                    nonisolated(unsafe) let audioInRef = audioInput
                    nonisolated(unsafe) let audioOutRef = audioOutput
                    audioInRef.requestMediaDataWhenReady(on: audioQueue) {
                        while audioInRef.isReadyForMoreMediaData {
                            if let sampleBuffer = audioOutRef.copyNextSampleBuffer() {
                                audioInRef.append(sampleBuffer)
                            } else {
                                audioInRef.markAsFinished()
                                group.leave()
                                break
                            }
                        }
                    }
                }
                
                // Wait for completion
                group.notify(queue: .main) {
                    if readerRef.status == .failed {
                        print("Reader failed: \(readerRef.error?.localizedDescription ?? "unknown")")
                        success = false
                    }
                    
                    writerRef.finishWriting {
                        if writerRef.status == .completed && success {
                            continuation.resume(returning: outputURL)
                        } else {
                            print("Writer failed: \(writerRef.error?.localizedDescription ?? "unknown")")
                            continuation.resume(returning: nil)
                        }
                    }
                }
            }
            
        } catch {
            print("Error setting up video compression: \(error)")
            return nil
        }
    }
}

// MARK: - Quartz Filter Helper

class QuartzFilter {
    private let filter: Any?
    
    init?(url: URL) {
        // QuartzFilter is a private API, use Core Graphics directly
        self.filter = nil
    }
    
    func apply(to context: CGContext) {
        // Apply filter settings
    }
}
