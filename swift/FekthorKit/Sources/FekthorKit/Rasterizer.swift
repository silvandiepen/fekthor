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

    /// Render the document. `scale` > 1 renders a crisper, higher-resolution
    /// raster (for zoomable previews); geometry is resolution-independent.
    public static func render(
        _ doc: VectorDocument, smoothing: Double = 1, scale: Double = 1,
        background: RGB? = (255, 255, 255)
    )
        -> RasterImage
    {
        let w = max(1, Int((Double(doc.width) * scale).rounded()))
        let h = max(1, Int((Double(doc.height) * scale).rounded()))
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        data.withUnsafeMutableBytes { buf in
            guard
                let ctx = CGContext(
                    data: buf.baseAddress, width: w, height: h,
                    bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            // White base by default so uncovered pixels compare against a
            // neutral background; tests can request nil for transparent logos.
            if let background {
                ctx.setFillColor(cgColor([background.r, background.g, background.b]))
                ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            }
            // Flip to a top-left origin so points map directly, then apply scale.
            ctx.translateBy(x: 0, y: CGFloat(h))
            ctx.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))

            // One shared CGPath builder (CGPathBuilder) drives both this preview
            // and the SVG export, so they cannot diverge (plan 02).
            for el in doc.elements {
                switch el {
                case .fill(let f):
                    let path = CGPathBuilder.fillPath(f.geometry, smoothing: smoothing)
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
                    guard s.refined != nil || s.points.count >= 2 else { continue }
                    let path = CGPathBuilder.strokePath(s, smoothing: smoothing)
                    ctx.addPath(path)
                    ctx.setStrokeColor(cgColor(s.color))
                    ctx.setLineWidth(CGFloat(s.width))
                    switch s.cap {
                    case .round: ctx.setLineCap(.round)
                    case .butt: ctx.setLineCap(.butt)
                    case .square: ctx.setLineCap(.square)
                    }
                    ctx.setLineJoin(.round)
                    ctx.strokePath()
                }
            }
        }
        RasterImage.unpremultiplyRGBA(&data)
        return RasterImage(width: w, height: h, data: data)
    }
}
