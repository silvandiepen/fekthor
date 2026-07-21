import Foundation

/// Opt-in taper (plan 03 §4, default off — editability first, D-014). When a
/// stroke's dt-width profile falls monotonically over its final ≥3×width to below
/// 40% of the stroke's median width, that tail is not a faithful constant-width
/// stroke: it is a brush tip. Rather than give up stroke semantics for the whole
/// path, only the tail is emitted as an **outline fill** (the centreline offset by
/// ±dt, closed at the point) while the body stays a real stroke.
public enum TaperBuilder {
    public struct Result {
        /// The remaining constant-width stroke body (nil if the whole path tapered).
        public var body: RefinedPath?
        /// Closed outline fills for the narrowing tails (0, 1 or 2 — either end).
        public var tails: [RefinedPath]
    }

    /// Returns a taper split, or nil when neither end qualifies (leave as a stroke).
    public static func build(
        chain: [Pt], dt: [Double], medianWidth: Double, w: Int, h: Int, options: RefineOptions
    ) -> Result? {
        let pts = chain
        let n = pts.count
        // Need enough length for a body plus at least one tail.
        guard n >= 8, medianWidth > 1.5 else { return nil }

        func localWidth(_ p: Pt) -> Double {
            let xi = min(max(Int(p.x.rounded()), 0), w - 1)
            let yi = min(max(Int(p.y.rounded()), 0), h - 1)
            return 2 * dt[yi * w + xi]
        }
        let ws = pts.map { localWidth($0) }
        var arc = [Double](repeating: 0, count: n)
        for i in 1..<n {
            arc[i] = arc[i - 1] + dist(pts[i], pts[i - 1])
        }
        let total = arc[n - 1]
        let tailLen = 3 * medianWidth
        guard total > 2.2 * tailLen else { return nil }
        let tipMax = 0.4 * medianWidth
        let slack = 0.6  // allow small dt noise against strict monotonicity

        // End tail: last point below the tip threshold and width weakly decreasing
        // over the final tailLen. Returns the split index (start of the tail).
        func endTail() -> Int? {
            guard ws[n - 1] < tipMax else { return nil }
            var s = n - 1
            while s > 0 && total - arc[s] < tailLen { s -= 1 }
            guard s >= 2 else { return nil }
            for i in (s + 1)..<n where ws[i] > ws[i - 1] + slack { return nil }
            return s
        }
        func startTail() -> Int? {
            guard ws[0] < tipMax else { return nil }
            var e = 0
            while e < n - 1 && arc[e] < tailLen { e += 1 }
            guard e <= n - 3 else { return nil }
            for i in 0..<e where ws[i] > ws[i + 1] + slack { return nil }
            return e
        }

        let endS = endTail()
        let startE = startTail()
        guard endS != nil || startE != nil else { return nil }

        // Body span [lo, hi] after removing qualifying tails; keep them disjoint.
        var lo = 0
        var hi = n - 1
        var tails: [RefinedPath] = []
        if let e = startE, e < (endS ?? n) {
            tails.append(outlineFill(Array(pts[0...e]), Array(ws[0...e])))
            lo = e
        }
        if let s = endS, s > lo + 1 {
            tails.append(outlineFill(Array(pts[s...(n - 1)]), Array(ws[s...(n - 1)])))
            hi = s
        }
        var body: RefinedPath?
        if hi - lo >= 2 {
            body = PathRefine.refine(Array(pts[lo...hi]), closed: false, options: options)
        }
        if body == nil && tails.isEmpty { return nil }
        return Result(body: body, tails: tails)
    }

    /// Build a closed outline polygon from a centreline segment and its per-point
    /// widths: offset ±width/2 along the local normal, down one side and back the
    /// other, so the tip (width → 0) closes to a point. Emitted as a refined path
    /// of straight segments (a real fill, the one sanctioned outline expansion).
    static func outlineFill(_ seg: [Pt], _ ws: [Double]) -> RefinedPath {
        let m = seg.count
        func normal(_ i: Int) -> Pt {
            let a = seg[max(0, i - 1)]
            let b = seg[min(m - 1, i + 1)]
            let dx = b.x - a.x
            let dy = b.y - a.y
            let len = (dx * dx + dy * dy).squareRoot()
            if len < 1e-9 { return Pt(0, 0) }
            return Pt(-dy / len, dx / len)  // left normal
        }
        var left: [Pt] = []
        var right: [Pt] = []
        for i in 0..<m {
            let nrm = normal(i)
            let half = max(0, ws[i] / 2)
            left.append(Pt(seg[i].x + nrm.x * half, seg[i].y + nrm.y * half))
            right.append(Pt(seg[i].x - nrm.x * half, seg[i].y - nrm.y * half))
        }
        // Order: left side forward, then right side backward → closed loop.
        var ring: [Pt] = left
        ring.append(contentsOf: right.reversed())
        let start = ring.first!
        var segs: [RefinedSegment] = []
        for i in 1..<ring.count {
            segs.append(.line(to: ring[i]))
        }
        return RefinedPath(start: start, segments: segs, closed: true)
    }

    @inline(__always) static func dist(_ a: Pt, _ b: Pt) -> Double {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }
}
