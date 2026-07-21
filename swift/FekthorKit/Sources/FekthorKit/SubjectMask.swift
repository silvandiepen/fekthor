import CoreVideo
import Foundation
import Vision

/// On-device ML part awareness (docs/AI.md: models assist, never replace, the
/// deterministic pipeline). Uses Vision's foreground instance segmentation —
/// built into macOS 14+, no model download — to produce per-pixel *part labels*
/// ("walls"): subject instances vs background. Downstream stages must not merge
/// regions across a wall, which is what keeps an occluding object (a brush, an
/// arm) structurally separate from what it overlaps.
///
/// Model output is fixed for a given OS version but may change across OS
/// updates, so part awareness is opt-in and excluded from the deterministic
/// eval floors.
public enum SubjectMask {
    /// Per-pixel instance labels at the image's size (0 = background,
    /// 1…k = foreground instances), or nil when unavailable (older OS, no
    /// subject found, or Vision failure). Never throws — ML assistance
    /// degrades to "off", it never breaks a conversion.
    public static func instanceLabels(_ img: RasterImage) -> [Int]? {
        guard #available(macOS 14.0, *) else { return nil }
        guard let cg = img.cgImage() else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let obs = request.results?.first, !obs.allInstances.isEmpty else { return nil }

        // The observation's instanceMask is a low-resolution OneComponent8
        // buffer whose pixel values are instance indices. Nearest-neighbour
        // scale it to the working size — walls only need part-level precision.
        let mask = obs.instanceMask
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return nil }
        let mw = CVPixelBufferGetWidth(mask)
        let mh = CVPixelBufferGetHeight(mask)
        let stride = CVPixelBufferGetBytesPerRow(mask)
        let bytes = base.assumingMemoryBound(to: UInt8.self)

        let w = img.width
        let h = img.height
        var labels = [Int](repeating: 0, count: w * h)
        var any = false
        for y in 0..<h {
            let my = min(mh - 1, y * mh / h)
            let rowBase = my * stride
            for x in 0..<w {
                let mx = min(mw - 1, x * mw / w)
                let v = Int(bytes[rowBase + mx])
                labels[y * w + x] = v
                if v > 0 { any = true }
            }
        }
        return any ? labels : nil
    }
}
