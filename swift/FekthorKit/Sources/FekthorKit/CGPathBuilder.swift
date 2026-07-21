import CoreGraphics
import Foundation

/// The single place that turns document geometry into a `CGPath`. The Rasterizer
/// renders through this so the CoreGraphics preview and the SVG export (which
/// emits the same lines/arcs/cubics/primitives) cannot diverge — preview ==
/// export by construction (plan 02).
///
/// Coordinate space: the Rasterizer flips its context so drawing happens in a
/// y-down space that matches `Pt` directly. Arc angles are therefore computed
/// with `atan2` in that same y-down space and passed straight to `addArc`.
public enum CGPathBuilder {
    @inline(__always) static func cg(_ p: Pt) -> CGPoint { CGPoint(x: p.x, y: p.y) }

    /// A fill path for a shape's geometry (outer + holes, even-odd).
    public static func fillPath(_ geometry: ShapeGeometry, smoothing: Double) -> CGPath {
        let path = CGMutablePath()
        switch geometry {
        case .rings(let rings):
            for ring in rings where ring.count >= 3 {
                appendLegacyRing(ring, smoothing: smoothing, to: path)
            }
        case .refined(let paths):
            for rp in paths { appendRefined(rp, to: path) }
        case .circle(let c, let r):
            path.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        case .ellipse(let c, let rx, let ry, let rot):
            var t = CGAffineTransform(translationX: c.x, y: c.y)
            t = t.rotated(by: rot)
            path.addEllipse(in: CGRect(x: -rx, y: -ry, width: 2 * rx, height: 2 * ry), transform: t)
        case .rect(let c, let w, let h, let rot, let cr):
            var t = CGAffineTransform(translationX: c.x, y: c.y)
            t = t.rotated(by: rot)
            let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
            let r = min(cr, min(w, h) / 2)
            if r > 0.01 {
                path.addRoundedRect(in: rect, cornerWidth: r, cornerHeight: r, transform: t)
            } else {
                path.addRect(rect, transform: t)
            }
        }
        return path
    }

    /// A stroke path (open or closed centreline).
    public static func strokePath(_ stroke: StrokePath, smoothing: Double) -> CGPath {
        let path = CGMutablePath()
        if let rp = stroke.refined {
            appendRefined(rp, to: path)
        } else {
            guard stroke.points.count >= 2 else { return path }
            let (start, segs) =
                stroke.closed
                ? PathBuilder.closed(stroke.points, strength: smoothing)
                : PathBuilder.open(stroke.points, strength: smoothing)
            path.move(to: cg(start))
            for s in segs {
                path.addCurve(to: cg(s.end), control1: cg(s.c1), control2: cg(s.c2))
            }
            if stroke.closed { path.closeSubpath() }
        }
        return path
    }

    /// Append a refined path (typed segments) to a CGPath.
    public static func appendRefined(_ rp: RefinedPath, to path: CGMutablePath) {
        path.move(to: cg(rp.start))
        for seg in rp.segments {
            switch seg {
            case .line(let to):
                path.addLine(to: cg(to))
            case .arc(let c, let r, let sa, let ea, let cw):
                // `cw` means increasing atan2 angle. The Rasterizer draws in a
                // y-flipped context, where CG's `clockwise` is the *decreasing*
                // angle direction — so the flag passed to CG is inverted.
                path.addArc(
                    center: cg(c), radius: CGFloat(r), startAngle: CGFloat(sa),
                    endAngle: CGFloat(ea), clockwise: !cw)
            case .cubic(let c1, let c2, let to):
                path.addCurve(to: cg(to), control1: cg(c1), control2: cg(c2))
            }
        }
        if rp.closed { path.closeSubpath() }
    }

    static func appendLegacyRing(_ ring: [Pt], smoothing: Double, to path: CGMutablePath) {
        let (start, segs) = PathBuilder.closed(ring, strength: smoothing)
        path.move(to: cg(start))
        for s in segs {
            path.addCurve(to: cg(s.end), control1: cg(s.c1), control2: cg(s.c2))
        }
        path.closeSubpath()
    }
}
