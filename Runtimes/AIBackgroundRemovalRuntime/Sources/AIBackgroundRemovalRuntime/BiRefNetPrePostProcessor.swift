import Foundation
import CoreImage
import ImageIO
import Accelerate
import UniformTypeIdentifiers
@preconcurrency import OnnxRuntimeBindings

enum BiRefNetPrePostError: LocalizedError {
    case invalidImage
    case resizeFailed
    case tensorCreationFailed
    case invalidModelOutput
    case outputEncodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Failed to decode image for BiRefNet processing."
        case .resizeFailed:
            return "Failed to resize image for model input."
        case .tensorCreationFailed:
            return "Failed to create model tensor input."
        case .invalidModelOutput:
            return "BiRefNet returned invalid output."
        case .outputEncodingFailed:
            return "Failed to encode transparent output image."
        }
    }
}

struct BiRefNetPreparedInput: @unchecked Sendable {
    nonisolated let tensorData: Data
    nonisolated let shape: [NSNumber]
    nonisolated let originalImage: CGImage
}

enum BiRefNetPrePostProcessor {
    nonisolated static let modelWidth = 1024
    nonisolated static let modelHeight = 1024

    nonisolated private static let mean: [Float] = [0.485, 0.456, 0.406]
    nonisolated private static let std: [Float] = [0.229, 0.224, 0.225]
    nonisolated static func prepareInput(from imageURL: URL) throws -> BiRefNetPreparedInput {
        let orientedImage = try loadOrientedImage(from: imageURL)
        return try prepareInput(from: orientedImage)
    }

    nonisolated static func prepareInput(from image: CGImage) throws -> BiRefNetPreparedInput {
        let resizedImage = try resizeToModelInput(image)
        let modelPixels = try rgbaPixels(from: resizedImage)

        let totalPixels = modelWidth * modelHeight
        let hw = totalPixels
        var tensor = [Float](repeating: 0, count: 3 * totalPixels)

        var maxPixel: Float = 0
        for idx in stride(from: 0, to: modelPixels.count, by: 4) {
            maxPixel = max(maxPixel, Float(modelPixels[idx]))
            maxPixel = max(maxPixel, Float(modelPixels[idx + 1]))
            maxPixel = max(maxPixel, Float(modelPixels[idx + 2]))
        }
        let normalizationDivisor = max(maxPixel, 1e-6)

        for pixelIndex in 0..<totalPixels {
            let rgbaIndex = pixelIndex * 4
            let r = Float(modelPixels[rgbaIndex]) / normalizationDivisor
            let g = Float(modelPixels[rgbaIndex + 1]) / normalizationDivisor
            let b = Float(modelPixels[rgbaIndex + 2]) / normalizationDivisor

            tensor[pixelIndex] = (r - mean[0]) / std[0]
            tensor[hw + pixelIndex] = (g - mean[1]) / std[1]
            tensor[(2 * hw) + pixelIndex] = (b - mean[2]) / std[2]
        }

        let tensorData = tensor.withUnsafeBufferPointer { Data(buffer: $0) }

        let shape: [NSNumber] = [1, 3, NSNumber(value: modelHeight), NSNumber(value: modelWidth)]
        return BiRefNetPreparedInput(tensorData: tensorData, shape: shape, originalImage: image)
    }

    nonisolated static func outputPNGData(from outputValue: ORTValue, originalImage: CGImage) throws -> Data {
        let tensorInfo = try outputValue.tensorTypeAndShapeInfo()
        let shape = tensorInfo.shape.map(\.intValue)
        guard shape.count >= 2 else {
            throw BiRefNetPrePostError.invalidModelOutput
        }

        let maskHeight = shape.count >= 4 ? shape[shape.count - 2] : modelHeight
        let maskWidth = shape.count >= 4 ? shape[shape.count - 1] : modelWidth
        guard maskWidth > 0, maskHeight > 0 else {
            throw BiRefNetPrePostError.invalidModelOutput
        }

        let outputData = try outputValue.tensorData() as Data
        let requiredFloatCount = maskWidth * maskHeight
        guard outputData.count >= requiredFloatCount * MemoryLayout<Float>.size else {
            throw BiRefNetPrePostError.invalidModelOutput
        }

        let probabilities: [Float] = outputData.withUnsafeBytes { rawBuffer in
            let floats = rawBuffer.bindMemory(to: Float.self)
            return Array(floats.prefix(requiredFloatCount))
        }

        var activated = [Float](repeating: 0, count: requiredFloatCount)
        var minValue = Float.greatestFiniteMagnitude
        var maxValue = -Float.greatestFiniteMagnitude

        for i in 0..<requiredFloatCount {
            let sigmoidValue = sigmoid(probabilities[i])
            activated[i] = sigmoidValue
            minValue = min(minValue, sigmoidValue)
            maxValue = max(maxValue, sigmoidValue)
        }

        let range = max(maxValue - minValue, 1e-6)
        var mask = [UInt8](repeating: 0, count: requiredFloatCount)
        for i in 0..<requiredFloatCount {
            let normalized = (activated[i] - minValue) / range
            mask[i] = UInt8(max(0, min(255, Int(round(normalized * 255.0)))))
        }

        let resizedMask = try resizeMask(
            mask,
            width: maskWidth,
            height: maskHeight,
            targetWidth: originalImage.width,
            targetHeight: originalImage.height
        )

        var rgba = try rgbaPixels(from: originalImage)
        for i in 0..<(originalImage.width * originalImage.height) {
            rgba[(i * 4) + 3] = resizedMask[i]
        }

        return try encodePNG(width: originalImage.width, height: originalImage.height, rgbaPixels: rgba)
    }

    nonisolated private static func loadOrientedImage(from url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw BiRefNetPrePostError.invalidImage
        }

        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientationRaw = (props?[kCGImagePropertyOrientation] as? NSNumber)?.int32Value ?? 1

        guard orientationRaw != 1 else {
            return image
        }

        let ciImage = CIImage(cgImage: image).oriented(forExifOrientation: orientationRaw)
        let ciContext = CIContext(options: nil)
        guard let oriented = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return image
        }
        return oriented
    }

    nonisolated private static func resizeToModelInput(_ image: CGImage) throws -> CGImage {
        var src = try rgbaPixels(from: image)
        var dst = [UInt8](repeating: 0, count: modelWidth * modelHeight * 4)

        let srcRowBytes = image.width * 4
        let dstRowBytes = modelWidth * 4

        let scaleError: vImage_Error = src.withUnsafeMutableBytes { srcBytes in
            dst.withUnsafeMutableBytes { dstBytes in
                var srcBuffer = vImage_Buffer(
                    data: srcBytes.baseAddress!,
                    height: vImagePixelCount(image.height),
                    width: vImagePixelCount(image.width),
                    rowBytes: srcRowBytes
                )
                var dstBuffer = vImage_Buffer(
                    data: dstBytes.baseAddress!,
                    height: vImagePixelCount(modelHeight),
                    width: vImagePixelCount(modelWidth),
                    rowBytes: dstRowBytes
                )
                return vImageScale_ARGB8888(&srcBuffer, &dstBuffer, nil, vImage_Flags(kvImageHighQualityResampling))
            }
        }

        guard scaleError == kvImageNoError else {
            throw BiRefNetPrePostError.resizeFailed
        }

        return try makeCGImage(width: modelWidth, height: modelHeight, rgbaPixels: dst)
    }

    nonisolated private static func resizeMask(
        _ srcMask: [UInt8],
        width: Int,
        height: Int,
        targetWidth: Int,
        targetHeight: Int
    ) throws -> [UInt8] {
        var src = srcMask
        var dst = [UInt8](repeating: 0, count: targetWidth * targetHeight)

        let scaleError: vImage_Error = src.withUnsafeMutableBytes { srcBytes in
            dst.withUnsafeMutableBytes { dstBytes in
                var srcBuffer = vImage_Buffer(
                    data: srcBytes.baseAddress!,
                    height: vImagePixelCount(height),
                    width: vImagePixelCount(width),
                    rowBytes: width
                )
                var dstBuffer = vImage_Buffer(
                    data: dstBytes.baseAddress!,
                    height: vImagePixelCount(targetHeight),
                    width: vImagePixelCount(targetWidth),
                    rowBytes: targetWidth
                )
                return vImageScale_Planar8(&srcBuffer, &dstBuffer, nil, vImage_Flags(kvImageHighQualityResampling))
            }
        }

        guard scaleError == kvImageNoError else {
            throw BiRefNetPrePostError.resizeFailed
        }

        return dst
    }

    nonisolated private static func rgbaPixels(from image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            .union(.byteOrder32Big)
        guard let context = CGContext(
            data: &bytes,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            throw BiRefNetPrePostError.invalidImage
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes
    }

    nonisolated private static func makeCGImage(width: Int, height: Int, rgbaPixels: [UInt8]) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            .union(.byteOrder32Big)

        guard let provider = CGDataProvider(data: Data(rgbaPixels) as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            throw BiRefNetPrePostError.outputEncodingFailed
        }

        return image
    }

    nonisolated private static func encodePNG(width: Int, height: Int, rgbaPixels: [UInt8]) throws -> Data {
        let image = try makeCGImage(width: width, height: height, rgbaPixels: rgbaPixels)
        let mutableData = NSMutableData()

        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw BiRefNetPrePostError.outputEncodingFailed
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw BiRefNetPrePostError.outputEncodingFailed
        }

        return mutableData as Data
    }

    nonisolated private static func sigmoid(_ value: Float) -> Float {
        if value >= 0 {
            let z = exp(-value)
            return 1 / (1 + z)
        }

        let z = exp(value)
        return z / (1 + z)
    }
}
