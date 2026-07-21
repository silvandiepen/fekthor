import CoreGraphics
import CoreML
import CoreVideo
import Foundation

/// On-device Real-ESRGAN 4× upscaling for small sources (docs/AI.md: optional
/// model, removable, deterministic fallback). Small logos/icons vectorise far
/// better after enhancement — more pixels for the same geometry.
///
/// The model is an optional local asset (~33 MB), NOT bundled: it is looked up
/// in Application Support and the feature simply reports unavailable without
/// it. Weights come from the owner's ImageKid Core ML conversion of
/// RealESRGAN_x4plus (see imageKid/tools/coreml-conversion).
public enum Enhance {
    static var modelURL: URL { ModelStore.compiledURL(.realESRGAN) }

    /// Sources above this size don't need enhancement (and single-pass
    /// inference stays bounded: 512² in → 2048² out).
    public static let maxInputSide = 512

    public static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: modelURL.path)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: MLModel?

    static func model() -> MLModel? {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        guard isAvailable else { return nil }
        let config = MLModelConfiguration()
        config.computeUnits = .all
        cached = try? MLModel(contentsOf: modelURL, configuration: config)
        return cached
    }

    /// 4× upscale, or nil when the model is missing/fails or the source is too
    /// large — the caller falls back to the unenhanced image (never breaks).
    public static func upscale4x(_ img: RasterImage) -> RasterImage? {
        guard max(img.width, img.height) <= maxInputSide, min(img.width, img.height) >= 16,
            let model = model(), let cg = img.cgImage(),
            let buffer = bgraBuffer(from: cg)
        else { return nil }
        guard
            let provider = try? MLDictionaryFeatureProvider(
                dictionary: ["input": MLFeatureValue(pixelBuffer: buffer)]),
            let result = try? model.prediction(from: provider),
            let outBuffer = result.featureValue(for: "output")?.imageBufferValue,
            let outCG = cgImage(from: outBuffer),
            let out = try? RasterImage.from(cgImage: outCG)
        else { return nil }
        return out
    }

    // MARK: - Pixel buffer plumbing

    static func bgraBuffer(from cg: CGImage) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        CVPixelBufferCreate(
            kCFAllocatorDefault, cg.width, cg.height, kCVPixelFormatType_32BGRA,
            attrs as CFDictionary, &pb)
        guard let buffer = pb else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard
            let ctx = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer), width: cg.width, height: cg.height,
                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        return buffer
    }

    static func cgImage(from buffer: CVPixelBuffer) -> CGImage? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)
        guard
            let ctx = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer), width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        return ctx.makeImage()
    }
}
