import Foundation

/// Convert simplified polylines into smooth cubic-Bézier segments
/// (interpolating Catmull-Rom). Used by both the SVG exporter and the
/// CoreGraphics rasterizer so preview and export are identical. Because
/// Catmull-Rom passes through every input point, shared boundary points stay
/// shared — smoothing does not reopen gaps between adjacent shapes.
public enum PathBuilder {
    /// A cubic segment: two control points and the end point (start is implicit).
    public struct Cubic {
        public var c1: Pt
        public var c2: Pt
        public var end: Pt
    }

    @inline(__always)
    private static func cubic(_ p0: Pt, _ p1: Pt, _ p2: Pt, _ p3: Pt) -> Cubic {
        let c1 = Pt(p1.x + (p2.x - p0.x) / 6.0, p1.y + (p2.y - p0.y) / 6.0)
        let c2 = Pt(p2.x - (p3.x - p1.x) / 6.0, p2.y - (p3.y - p1.y) / 6.0)
        return Cubic(c1: c1, c2: c2, end: p2)
    }

    /// Smooth an open polyline. Returns the start point and cubic segments.
    public static func open(_ pts: [Pt]) -> (start: Pt, segs: [Cubic]) {
        guard pts.count >= 2 else { return (pts.first ?? Pt(0, 0), []) }
        if pts.count == 2 {
            return (pts[0], [Cubic(c1: pts[0], c2: pts[1], end: pts[1])])
        }
        var segs: [Cubic] = []
        let n = pts.count
        for i in 0..<(n - 1) {
            let p0 = pts[max(0, i - 1)]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = pts[min(n - 1, i + 2)]
            segs.append(cubic(p0, p1, p2, p3))
        }
        return (pts[0], segs)
    }

    /// Smooth a closed ring. Returns the start point and cubic segments; the
    /// final segment returns to the start.
    public static func closed(_ ring: [Pt]) -> (start: Pt, segs: [Cubic]) {
        let n = ring.count
        guard n >= 3 else { return open(ring) }
        var segs: [Cubic] = []
        for i in 0..<n {
            let p0 = ring[(i - 1 + n) % n]
            let p1 = ring[i]
            let p2 = ring[(i + 1) % n]
            let p3 = ring[(i + 2) % n]
            segs.append(cubic(p0, p1, p2, p3))
        }
        return (ring[0], segs)
    }
}
