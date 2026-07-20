import CoreGraphics
import Foundation

/// Render a vector document back to a raster buffer with CoreGraphics.
///
/// This is the engine-neutral reference renderer used to validate that the
/// vector reproduces the source (render-back comparison). Fills use the even-odd
/// rule; strokes keep real width, round caps and joins.
public enum Rasterizer {
    static func cgColor(_ rgb: [UInt8]) -> CGColor {
        CGColor(
            srgbRed: CGFloat(rgb[0]) / 255, green: CGFloat(rgb[1]) / 255,
            blue: CGFloat(rgb[2]) / 255, alpha: 1)
    }

    public static func render(_ doc: VectorDocument) -> RasterImage {
        let w = doc.width
        let h = doc.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        data.withUnsafeMutableBytes { buf in
            guard
                let ctx = CGContext(
                    data: buf.baseAddress, width: w, height: h,
                    bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            // White base so uncovered pixels compare against a neutral background.
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            // Flip to a top-left origin so points map directly.
            ctx.translateBy(x: 0, y: CGFloat(h))
            ctx.scaleBy(x: 1, y: -1)

            for el in doc.elements {
                switch el {
                case .fill(let f):
                    let path = CGMutablePath()
                    for ring in f.rings where ring.count >= 3 {
                        path.move(to: CGPoint(x: ring[0].x, y: ring[0].y))
                        for p in ring.dropFirst() {
                            path.addLine(to: CGPoint(x: p.x, y: p.y))
                        }
                        path.closeSubpath()
                    }
                    switch f.paint {
                    case .solid(let rgb):
                        ctx.addPath(path)
                        ctx.setFillColor(cgColor(rgb))
                        ctx.fillPath(using: .evenOdd)
                    case .linear(let grad):
                        ctx.saveGState()
                        ctx.addPath(path)
                        ctx.clip(using: .evenOdd)
                        let colors = grad.stops.map { cgColor($0.color) } as CFArray
                        let locations = grad.stops.map { CGFloat($0.offset) }
                        if let g = CGGradient(
                            colorsSpace: space, colors: colors, locations: locations)
                        {
                            ctx.drawLinearGradient(
                                g, start: CGPoint(x: grad.p0.x, y: grad.p0.y),
                                end: CGPoint(x: grad.p1.x, y: grad.p1.y),
                                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                        }
                        ctx.restoreGState()
                    }
                case .stroke(let s):
                    guard s.points.count >= 2 else { continue }
                    let path = CGMutablePath()
                    path.move(to: CGPoint(x: s.points[0].x, y: s.points[0].y))
                    for p in s.points.dropFirst() {
                        path.addLine(to: CGPoint(x: p.x, y: p.y))
                    }
                    if s.closed { path.closeSubpath() }
                    ctx.addPath(path)
                    ctx.setStrokeColor(cgColor(s.color))
                    ctx.setLineWidth(CGFloat(s.width))
                    ctx.setLineCap(.round)
                    ctx.setLineJoin(.round)
                    ctx.strokePath()
                }
            }
        }
        return RasterImage(width: w, height: h, data: data)
    }
}
