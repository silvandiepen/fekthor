import CoreGraphics
import Foundation
import Vision

/// A fillable region: one outer ring with zero or more holes.
public struct Region {
    public var paletteIdx: Int
    public var outer: [Pt]
    public var holes: [[Pt]]
    public var area: Double
}

public enum ContourTracer {
    /// Build a single-channel mask CGImage for one palette index.
    static func maskImage(_ q: Quantized, idx: Int) -> CGImage? {
        let w = q.width
        let h = q.height
        var buf = [UInt8](repeating: 0, count: w * h)
        var any = false
        for i in 0..<(w * h) where q.indices[i] == idx {
            buf[i] = 255
            any = true
        }
        if !any { return nil }
        let space = CGColorSpaceCreateDeviceGray()
        return buf.withUnsafeMutableBytes { p -> CGImage? in
            guard
                let ctx = CGContext(
                    data: p.baseAddress, width: w, height: h,
                    bitsPerComponent: 8, bytesPerRow: w, space: space,
                    bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return nil }
            return ctx.makeImage()
        }
    }

    /// Trace all fillable regions across every palette index using Vision.
    public static func regions(_ q: Quantized) -> [Region] {
        let w = Double(q.width)
        let h = Double(q.height)
        var out: [Region] = []
        let maxDim = CGFloat(max(q.width, q.height))

        func points(_ c: VNContour) -> [Pt] {
            c.normalizedPoints.map { p in
                Pt(Double(p.x) * w, (1.0 - Double(p.y)) * h)
            }
        }

        func collect(_ contour: VNContour, depth: Int, idx: Int) {
            if depth % 2 == 0 {
                let outer = points(contour)
                if outer.count >= 3 {
                    let holes = contour.childContours.map { points($0) }.filter { $0.count >= 3 }
                    out.append(
                        Region(
                            paletteIdx: idx, outer: outer, holes: holes,
                            area: Geometry.area(outer)))
                }
            }
            for child in contour.childContours {
                collect(child, depth: depth + 1, idx: idx)
            }
        }

        for idx in 0..<q.palette.count {
            guard let cg = maskImage(q, idx: idx) else { continue }
            let request = VNDetectContoursRequest()
            request.contrastAdjustment = 1.0
            request.detectsDarkOnLight = false
            request.maximumImageDimension = Int(maxDim)
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continue
            }
            guard let obs = request.results?.first as? VNContoursObservation else { continue }
            for top in obs.topLevelContours {
                collect(top, depth: 0, idx: idx)
            }
        }
        return out
    }
}
