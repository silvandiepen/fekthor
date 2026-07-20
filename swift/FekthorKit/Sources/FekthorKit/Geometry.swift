import Foundation

/// A 2D point in source-image pixel coordinates (origin top-left, y down).
public struct Pt: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }
}

public enum Geometry {
    /// Signed area of a closed ring (shoelace). Positive = counter-clockwise.
    public static func signedArea(_ ring: [Pt]) -> Double {
        let n = ring.count
        if n < 3 { return 0 }
        var a = 0.0
        for i in 0..<n {
            let p = ring[i]
            let q = ring[(i + 1) % n]
            a += p.x * q.y - q.x * p.y
        }
        return a / 2
    }

    public static func area(_ ring: [Pt]) -> Double { abs(signedArea(ring)) }

    private static func perpDist(_ p: Pt, _ a: Pt, _ b: Pt) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len = (dx * dx + dy * dy).squareRoot()
        if len < 1e-9 {
            let ex = p.x - a.x
            let ey = p.y - a.y
            return (ex * ex + ey * ey).squareRoot()
        }
        return abs((p.x - a.x) * dy - (p.y - a.y) * dx) / len
    }

    /// Douglas-Peucker simplification of an open polyline (iterative).
    public static func simplifyOpen(_ pts: [Pt], epsilon: Double) -> [Pt] {
        if pts.count < 3 { return pts }
        let n = pts.count
        var keep = [Bool](repeating: false, count: n)
        keep[0] = true
        keep[n - 1] = true
        var stack: [(Int, Int)] = [(0, n - 1)]
        while let (s, e) = stack.popLast() {
            var dmax = 0.0
            var index = 0
            if e > s + 1 {
                for i in (s + 1)..<e {
                    let d = perpDist(pts[i], pts[s], pts[e])
                    if d > dmax {
                        dmax = d
                        index = i
                    }
                }
            }
            if dmax > epsilon {
                keep[index] = true
                stack.append((s, index))
                stack.append((index, e))
            }
        }
        var out: [Pt] = []
        for i in 0..<n where keep[i] { out.append(pts[i]) }
        return out
    }

    /// Simplify a closed ring while preserving closure. Anchors at the vertex
    /// furthest from the first so the result is stable under ring rotation.
    public static func simplifyClosed(_ ring: [Pt], epsilon: Double) -> [Pt] {
        let n = ring.count
        if n < 4 { return ring }
        let a = ring[0]
        var far = 0
        var fardist = 0.0
        for i in 0..<n {
            let d = pow(ring[i].x - a.x, 2) + pow(ring[i].y - a.y, 2)
            if d > fardist {
                fardist = d
                far = i
            }
        }
        var chain: [Pt] = []
        chain.reserveCapacity(n + 1)
        for i in 0...n { chain.append(ring[(far + i) % n]) }
        var simplified = simplifyOpen(chain, epsilon: epsilon)
        if simplified.count > 1 { simplified.removeLast() }
        return simplified
    }
}
