import Foundation

/// A typed segment in a refined path. Start point is implicit (previous
/// segment's end, or the path's `start`).
public enum RefinedSegment: Sendable, Equatable {
    case line(to: Pt)
    case arc(center: Pt, radius: Double, startAngle: Double, endAngle: Double, clockwise: Bool)
    case cubic(c1: Pt, c2: Pt, to: Pt)

    /// The point this segment ends at (used to reconstruct anchor sequences).
    public var endPoint: Pt {
        switch self {
        case .line(let to): return to
        case .arc(let c, let r, _, let end, _):
            return Pt(c.x + r * cos(end), c.y + r * sin(end))
        case .cubic(_, _, let to): return to
        }
    }
}

/// An intentional path: a start point followed by typed segments. Replaces the
/// "many small cubic steps through every point" produced by Catmull-Rom.
public struct RefinedPath: Sendable, Equatable {
    public var start: Pt
    public var segments: [RefinedSegment]
    public var closed: Bool
    public init(start: Pt, segments: [RefinedSegment], closed: Bool) {
        self.start = start
        self.segments = segments
        self.closed = closed
    }

    /// Node count for simplicity scoring: anchor points (start + one per segment).
    public var nodeCount: Int { segments.count + 1 }
}

public struct RefineOptions: Sendable {
    /// Max deviation from the input points, px (driven from Detail).
    public var tolerance: Double
    /// Corner if the local turn angle exceeds this (degrees). Default 32°.
    public var cornerAngle: Double
    /// 0…1 UI option; scales the line-fit tolerance so straightening is greedier.
    public var straighten: Double
    /// Existing smoothing strength; blends fitted cubics toward their chord.
    public var smoothing: Double
    public init(
        tolerance: Double = 1.5, cornerAngle: Double = 32, straighten: Double = 0.5,
        smoothing: Double = 1.0
    ) {
        self.tolerance = tolerance
        self.cornerAngle = cornerAngle
        self.straighten = straighten
        self.smoothing = smoothing
    }
}

/// Convert a dense polyline (pre-Douglas-Peucker, so no data is lost) into an
/// intentional `RefinedPath`: straight runs become one line, roundings become
/// arcs or fitted cubics, and detected corners become hard anchors that no
/// segment may cross. Deterministic — no randomness, no hash-set iteration.
///
/// **Corner anchors are hard constraints** (guardrail): smoothing never rounds
/// through one, and — crucially for the shared-edge gap invariant — every
/// segment's endpoints are the exact input anchor points, never moved. A future
/// "round corners" feature would relax `cornerAngle`, not bypass anchors.
public enum PathRefine {
    // MARK: - Public entry

    public static func refine(_ input: [Pt], closed: Bool, options: RefineOptions) -> RefinedPath {
        let pts = dedupe(input)
        guard pts.count >= 2 else {
            return RefinedPath(start: pts.first ?? Pt(0, 0), segments: [], closed: closed)
        }
        return closed ? refineClosed(pts, options) : refineOpen(pts, options)
    }

    // MARK: - Open / closed drivers

    static func refineOpen(_ pts: [Pt], _ opt: RefineOptions) -> RefinedPath {
        let corners = detectCorners(pts, closed: false, opt)
        var anchors = [0]
        anchors.append(contentsOf: corners)
        anchors.append(pts.count - 1)
        var segs: [RefinedSegment] = []
        for i in 0..<(anchors.count - 1) {
            let span = Array(pts[anchors[i]...anchors[i + 1]])
            segs.append(contentsOf: fitSpan(span, opt))
        }
        return RefinedPath(start: pts[0], segments: segs, closed: false)
    }

    static func refineClosed(_ pts: [Pt], _ opt: RefineOptions) -> RefinedPath {
        let corners = detectCorners(pts, closed: true, opt)
        if corners.isEmpty {
            // Seam the loop at index 0 (already canonicalised upstream) and fit
            // the whole loop as one span; a true circle is caught by primitive
            // detection first, so what reaches here is a smooth non-circular loop.
            var span = pts
            span.append(pts[0])
            let segs = fitSpan(span, opt)
            return RefinedPath(start: pts[0], segments: segs, closed: true)
        }
        let anchors = corners.sorted()
        var segs: [RefinedSegment] = []
        let m = anchors.count
        for i in 0..<m {
            let a = anchors[i]
            let b = anchors[(i + 1) % m]
            let span = subchain(pts, a, b)
            segs.append(contentsOf: fitSpan(span, opt))
        }
        return RefinedPath(start: pts[anchors[0]], segments: segs, closed: true)
    }

    /// Points from index `a` to `b` inclusive, wrapping if `b <= a`.
    static func subchain(_ pts: [Pt], _ a: Int, _ b: Int) -> [Pt] {
        if b > a { return Array(pts[a...b]) }
        var out = Array(pts[a...])
        out.append(contentsOf: pts[0...b])
        return out
    }

    // MARK: - Per-span fitting (line → arc → cubic, first within tolerance)

    static func fitSpan(_ span: [Pt], _ opt: RefineOptions) -> [RefinedSegment] {
        guard span.count >= 2 else { return [] }
        if span.count == 2 { return [.line(to: span[1])] }
        if let l = tryLine(span, opt) { return [l] }
        if let a = tryArc(span, opt) { return [a] }
        return fitCubics(span, opt)
    }

    /// A straight run: every interior point within the (straighten-scaled)
    /// tolerance of the chord. Endpoints are preserved exactly (gap invariant).
    static func tryLine(_ span: [Pt], _ opt: RefineOptions) -> RefinedSegment? {
        let a = span.first!
        let b = span.last!
        let tol = opt.tolerance * (0.5 + opt.straighten)
        var maxD = 0.0
        for i in 1..<(span.count - 1) {
            maxD = max(maxD, perpDist(span[i], a, b))
        }
        return maxD <= tol ? .line(to: b) : nil
    }

    /// A circular arc through the span. The circle centre is placed on the
    /// perpendicular bisector of the two anchors using the least-squares radius,
    /// so the arc passes **exactly** through both anchors (continuity / gap
    /// invariant) while matching the interior points within tolerance.
    static func tryArc(_ span: [Pt], _ opt: RefineOptions) -> RefinedSegment? {
        let a = span.first!
        let b = span.last!
        let chord = dist(a, b)
        if chord < 1e-6 { return nil }  // closed seam span: no arc, use cubics
        guard let fit = kasaCircle(span) else { return nil }
        // Reject near-straight giant-radius arcs (those are lines) and tiny sweeps.
        let spanLen = polylineLength(span)
        if fit.r > 4 * spanLen { return nil }
        if fit.r < chord / 2 { return nil }  // radius too small to span the chord

        // Recentre on the bisector at |h| = sqrt(r² − (chord/2)²), on the side the
        // algebraic fit chose, so the arc endpoints coincide with the anchors.
        let mid = Pt((a.x + b.x) / 2, (a.y + b.y) / 2)
        var nx = -(b.y - a.y) / chord
        var ny = (b.x - a.x) / chord
        // Orient the normal toward the fitted centre.
        if (fit.cx - mid.x) * nx + (fit.cy - mid.y) * ny < 0 {
            nx = -nx
            ny = -ny
        }
        let h = (fit.r * fit.r - chord * chord / 4).squareRoot()
        let cx = mid.x + nx * h
        let cy = mid.y + ny * h
        let r = fit.r

        // Validate: interior points within tolerance of this circle.
        var maxD = 0.0
        for p in span {
            maxD = max(maxD, abs((dist(p, Pt(cx, cy))) - r))
        }
        if maxD > opt.tolerance { return nil }

        let startAngle = atan2(a.y - cy, a.x - cx)
        let endAngle = atan2(b.y - cy, b.x - cx)
        // Direction convention (used identically by flatten, CG and SVG): the arc
        // is traversed in the direction that reaches an interior sample within
        // less than a half-turn. In y-down space, increasing atan2 angle is
        // clockwise on screen, so `clockwise == true` means increasing angle.
        let midPt = span[span.count / 2]
        let midAng = atan2(midPt.y - cy, midPt.x - cx)
        var inc = midAng - startAngle
        while inc < 0 { inc += 2 * .pi }
        while inc >= 2 * .pi { inc -= 2 * .pi }
        let clockwise = inc < .pi
        let sweep = arcSweep(startAngle, endAngle, clockwise: clockwise)
        if sweep < 15 * .pi / 180 { return nil }
        return .arc(
            center: Pt(cx, cy), radius: r, startAngle: startAngle, endAngle: endAngle,
            clockwise: clockwise)
    }

    // MARK: - Corner detection

    /// Indices of corner anchors: points where the local turn (between the mean
    /// directions of the previous and next `k` samples) exceeds `cornerAngle`
    /// and is a local maximum. Corners are kept ≥ k apart to avoid clusters.
    static func detectCorners(_ pts: [Pt], closed: Bool, _ opt: RefineOptions) -> [Int] {
        let n = pts.count
        let k = min(8, max(3, n / 12))
        if n < 2 * k + 1 { return [] }
        let cornerRad = opt.cornerAngle * .pi / 180
        // Measure turn on lightly-smoothed positions so sub-pixel staircase jitter
        // does not read as a corner; real corners survive a small window.
        let sm = smoothPositions(pts, closed: closed, window: min(2, k - 1))
        var turn = [Double](repeating: 0, count: n)
        let lo = closed ? 0 : k
        let hi = closed ? n : n - k
        for i in lo..<hi {
            let iPrev = closed ? ((i - k + n) % n) : i - k
            let iNext = closed ? ((i + k) % n) : i + k
            let v1 = Pt(sm[i].x - sm[iPrev].x, sm[i].y - sm[iPrev].y)
            let v2 = Pt(sm[iNext].x - sm[i].x, sm[iNext].y - sm[i].y)
            turn[i] = abs(angleBetween(v1, v2))
        }
        var corners: [Int] = []
        for i in lo..<hi where turn[i] > cornerRad {
            let p = closed ? ((i - 1 + n) % n) : i - 1
            let q = closed ? ((i + 1) % n) : i + 1
            // Local maximum with a deterministic tie-break (strictly greater than
            // the successor, ≥ the predecessor).
            if turn[i] >= turn[p] && turn[i] > turn[q] {
                if let last = corners.last, i - last < k { continue }
                corners.append(i)
            }
        }
        return corners
    }

    // MARK: - Schneider cubic fitting

    static func fitCubics(_ span: [Pt], _ opt: RefineOptions) -> [RefinedSegment] {
        let n = span.count
        let leftT = normalize(Pt(span[1].x - span[0].x, span[1].y - span[0].y))
        let rightT = normalize(Pt(span[n - 2].x - span[n - 1].x, span[n - 2].y - span[n - 1].y))
        var beziers: [[Pt]] = []
        fitCubic(span, leftT, rightT, opt.tolerance, depth: 0, into: &beziers)
        var segs: [RefinedSegment] = []
        for b in beziers {
            let blended = blendCubic(b, smoothing: opt.smoothing)
            segs.append(.cubic(c1: blended[1], c2: blended[2], to: blended[3]))
        }
        return segs
    }

    /// Blend a cubic's control points toward the chord by (1 − smoothing) so the
    /// existing Smoothing slider keeps its meaning: 1 = full fitted curve, 0 =
    /// the polygonal chord (a straight line between the anchors).
    static func blendCubic(_ b: [Pt], smoothing: Double) -> [Pt] {
        if smoothing >= 1 { return b }
        let s = max(0, smoothing)
        let p0 = b[0]
        let p3 = b[3]
        let chord1 = Pt(p0.x + (p3.x - p0.x) / 3, p0.y + (p3.y - p0.y) / 3)
        let chord2 = Pt(p0.x + 2 * (p3.x - p0.x) / 3, p0.y + 2 * (p3.y - p0.y) / 3)
        let c1 = Pt(chord1.x + s * (b[1].x - chord1.x), chord1.y + s * (b[1].y - chord1.y))
        let c2 = Pt(chord2.x + s * (b[2].x - chord2.x), chord2.y + s * (b[2].y - chord2.y))
        return [p0, c1, c2, p3]
    }

    static func fitCubic(
        _ pts: [Pt], _ leftT: Pt, _ rightT: Pt, _ tol: Double, depth: Int, into out: inout [[Pt]]
    ) {
        let n = pts.count
        if n == 2 {
            let d = dist(pts[0], pts[1]) / 3
            out.append([
                pts[0], Pt(pts[0].x + leftT.x * d, pts[0].y + leftT.y * d),
                Pt(pts[1].x + rightT.x * d, pts[1].y + rightT.y * d), pts[1],
            ])
            return
        }
        var u = chordLengthParameterize(pts)
        var bezier = generateBezier(pts, u, leftT, rightT)
        var (maxError, splitPoint) = computeMaxError(pts, bezier, u)
        if maxError < tol {
            out.append(bezier)
            return
        }
        // A couple of Newton reparameterisation rounds before giving up (≤2, per plan).
        if maxError < tol * tol {
            for _ in 0..<2 {
                u = reparameterize(pts, bezier, u)
                bezier = generateBezier(pts, u, leftT, rightT)
                (maxError, splitPoint) = computeMaxError(pts, bezier, u)
                if maxError < tol {
                    out.append(bezier)
                    return
                }
            }
        }
        if depth >= 24 || splitPoint <= 0 || splitPoint >= n - 1 {
            out.append(bezier)  // stop recursing; accept the best fit
            return
        }
        let centerT = normalize(
            Pt(pts[splitPoint - 1].x - pts[splitPoint + 1].x,
                pts[splitPoint - 1].y - pts[splitPoint + 1].y))
        fitCubic(Array(pts[0...splitPoint]), leftT, centerT, tol, depth: depth + 1, into: &out)
        let rev = Pt(-centerT.x, -centerT.y)
        fitCubic(Array(pts[splitPoint...]), rev, rightT, tol, depth: depth + 1, into: &out)
    }

    static func chordLengthParameterize(_ pts: [Pt]) -> [Double] {
        var u = [Double](repeating: 0, count: pts.count)
        for i in 1..<pts.count { u[i] = u[i - 1] + dist(pts[i], pts[i - 1]) }
        let total = u.last ?? 1
        if total > 0 {
            for i in 1..<pts.count { u[i] /= total }
        }
        return u
    }

    /// Least-squares cubic with fixed endpoints and endpoint tangents (Schneider).
    static func generateBezier(_ pts: [Pt], _ u: [Double], _ leftT: Pt, _ rightT: Pt) -> [Pt] {
        let n = pts.count
        let first = pts[0]
        let last = pts[n - 1]
        var a0 = [Pt](repeating: Pt(0, 0), count: n)
        var a1 = [Pt](repeating: Pt(0, 0), count: n)
        for i in 0..<n {
            let b = bernstein(u[i])
            a0[i] = Pt(leftT.x * b.1, leftT.y * b.1)
            a1[i] = Pt(rightT.x * b.2, rightT.y * b.2)
        }
        var c00 = 0.0, c01 = 0.0, c11 = 0.0
        var x0 = 0.0, x1 = 0.0
        for i in 0..<n {
            c00 += a0[i].x * a0[i].x + a0[i].y * a0[i].y
            c01 += a0[i].x * a1[i].x + a0[i].y * a1[i].y
            c11 += a1[i].x * a1[i].x + a1[i].y * a1[i].y
            let b = bernstein(u[i])
            let tmp = Pt(
                pts[i].x - (first.x * (b.0 + b.1) + last.x * (b.2 + b.3)),
                pts[i].y - (first.y * (b.0 + b.1) + last.y * (b.2 + b.3)))
            x0 += a0[i].x * tmp.x + a0[i].y * tmp.y
            x1 += a1[i].x * tmp.x + a1[i].y * tmp.y
        }
        let det = c00 * c11 - c01 * c01
        var alphaL = 0.0, alphaR = 0.0
        if abs(det) > 1e-12 {
            alphaL = (x0 * c11 - x1 * c01) / det
            alphaR = (c00 * x1 - c01 * x0) / det
        }
        let segLen = dist(first, last)
        let epsilon = 1e-6 * segLen
        if alphaL < epsilon || alphaR < epsilon {
            // Fall back to Wu/Barsky heuristic (tangents scaled by 1/3 chord).
            let d = segLen / 3
            alphaL = d
            alphaR = d
            return [
                first, Pt(first.x + leftT.x * alphaL, first.y + leftT.y * alphaL),
                Pt(last.x + rightT.x * alphaR, last.y + rightT.y * alphaR), last,
            ]
        }
        return [
            first, Pt(first.x + leftT.x * alphaL, first.y + leftT.y * alphaL),
            Pt(last.x + rightT.x * alphaR, last.y + rightT.y * alphaR), last,
        ]
    }

    static func reparameterize(_ pts: [Pt], _ bez: [Pt], _ u: [Double]) -> [Double] {
        var out = u
        for i in 0..<pts.count { out[i] = newtonRaphsonRootFind(bez, pts[i], u[i]) }
        return out
    }

    static func newtonRaphsonRootFind(_ q: [Pt], _ p: Pt, _ u: Double) -> Double {
        let qu = bezierAt(q, u)
        // q' and q'' control points.
        var q1 = [Pt](repeating: Pt(0, 0), count: 3)
        for i in 0..<3 {
            q1[i] = Pt((q[i + 1].x - q[i].x) * 3, (q[i + 1].y - q[i].y) * 3)
        }
        var q2 = [Pt](repeating: Pt(0, 0), count: 2)
        for i in 0..<2 {
            q2[i] = Pt((q1[i + 1].x - q1[i].x) * 2, (q1[i + 1].y - q1[i].y) * 2)
        }
        let q1u = bezier2At(q1, u)
        let q2u = bezier1At(q2, u)
        let numerator = (qu.x - p.x) * q1u.x + (qu.y - p.y) * q1u.y
        let denominator =
            q1u.x * q1u.x + q1u.y * q1u.y + (qu.x - p.x) * q2u.x + (qu.y - p.y) * q2u.y
        if abs(denominator) < 1e-12 { return u }
        let next = u - numerator / denominator
        return min(1, max(0, next))
    }

    static func computeMaxError(_ pts: [Pt], _ bez: [Pt], _ u: [Double]) -> (Double, Int) {
        var maxDist = 0.0
        var splitPoint = pts.count / 2
        for i in 1..<(pts.count - 1) {
            let p = bezierAt(bez, u[i])
            let d = dist(p, pts[i])
            if d > maxDist {
                maxDist = d
                splitPoint = i
            }
        }
        return (maxDist, splitPoint)
    }

    // MARK: - Reversal (for shared chains traversed the other way)

    /// Reverse a refined path so both faces of a shared boundary can reference one
    /// cached result. Reversing is exact — the same curve, traversed backward — so
    /// the two faces stay point-identical (gap invariant, master plan §2).
    public static func reverse(_ path: RefinedPath) -> RefinedPath {
        // Reconstruct anchor points: start, then each segment's end.
        var anchors: [Pt] = [path.start]
        for s in path.segments { anchors.append(s.endPoint) }
        let n = path.segments.count
        var out: [RefinedSegment] = []
        for i in stride(from: n - 1, through: 0, by: -1) {
            let from = anchors[i]  // becomes the new segment's END
            switch path.segments[i] {
            case .line:
                out.append(.line(to: from))
            case .arc(let c, let r, let sa, let ea, let cw):
                // Same circle, swap start/end angle, flip direction.
                out.append(
                    .arc(center: c, radius: r, startAngle: ea, endAngle: sa, clockwise: !cw))
            case .cubic(let c1, let c2, _):
                // Swap control points; new end is the previous segment's start.
                out.append(.cubic(c1: c2, c2: c1, to: from))
            }
        }
        return RefinedPath(start: anchors[n], segments: out, closed: path.closed)
    }

    // MARK: - Flatten (for validation, area/bbox, primitive sampling)

    /// Sample a refined path back into a dense polyline. `arcStep` is the target
    /// spacing (radians) between arc samples; cubics use `cubicSamples` points.
    public static func flatten(_ path: RefinedPath, cubicSamples: Int = 12) -> [Pt] {
        var out: [Pt] = [path.start]
        var cur = path.start
        for seg in path.segments {
            switch seg {
            case .line(let to):
                out.append(to)
                cur = to
            case .arc(let c, let r, let sa, let ea, let cw):
                let sweep = arcSweep(sa, ea, clockwise: cw)
                let steps = max(2, Int((sweep / (2 * .pi)) * 64) + 2)
                for s in 1...steps {
                    let t = Double(s) / Double(steps)
                    let ang = cw ? sa + sweep * t : sa - sweep * t
                    out.append(Pt(c.x + r * cos(ang), c.y + r * sin(ang)))
                }
                cur = seg.endPoint
            case .cubic(let c1, let c2, let to):
                let b = [cur, c1, c2, to]
                for s in 1...cubicSamples {
                    out.append(bezierAt(b, Double(s) / Double(cubicSamples)))
                }
                cur = to
            }
        }
        return out
    }

    // MARK: - Math helpers

    /// Moving-average positions for corner measurement only (never for fitting).
    static func smoothPositions(_ pts: [Pt], closed: Bool, window: Int) -> [Pt] {
        let n = pts.count
        if window < 1 || n < 3 { return pts }
        var out = pts
        for i in 0..<n {
            var sx = 0.0, sy = 0.0, c = 0
            for d in -window...window {
                let j: Int
                if closed {
                    j = ((i + d) % n + n) % n
                } else {
                    j = i + d
                    if j < 0 || j >= n { continue }
                }
                sx += pts[j].x
                sy += pts[j].y
                c += 1
            }
            out[i] = Pt(sx / Double(c), sy / Double(c))
        }
        return out
    }

    static func dedupe(_ pts: [Pt]) -> [Pt] {
        guard let first = pts.first else { return [] }
        var out: [Pt] = [first]
        for p in pts.dropFirst() where dist(p, out.last!) > 1e-9 { out.append(p) }
        return out
    }

    static func kasaCircle(_ pts: [Pt]) -> (cx: Double, cy: Double, r: Double)? {
        let n = Double(pts.count)
        var sx = 0.0, sy = 0.0, sxx = 0.0, syy = 0.0, sxy = 0.0
        var sxz = 0.0, syz = 0.0, sz = 0.0
        for p in pts {
            let z = p.x * p.x + p.y * p.y
            sx += p.x
            sy += p.y
            sxx += p.x * p.x
            syy += p.y * p.y
            sxy += p.x * p.y
            sxz += p.x * z
            syz += p.y * z
            sz += z
        }
        // Solve [[sxx,sxy,sx],[sxy,syy,sy],[sx,sy,n]] · [A,B,C] = [sxz,syz,sz].
        let m = [[sxx, sxy, sx], [sxy, syy, sy], [sx, sy, n]]
        let rhs = [sxz, syz, sz]
        guard let sol = solve3(m, rhs) else { return nil }
        let cx = sol[0] / 2
        let cy = sol[1] / 2
        let r2 = sol[2] + cx * cx + cy * cy
        if r2 <= 0 { return nil }
        return (cx, cy, r2.squareRoot())
    }

    static func solve3(_ m: [[Double]], _ b: [Double]) -> [Double]? {
        let det =
            m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
            - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
            + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])
        if abs(det) < 1e-12 { return nil }
        func detCol(_ col: Int) -> Double {
            var mm = m
            for r in 0..<3 { mm[r][col] = b[r] }
            return mm[0][0] * (mm[1][1] * mm[2][2] - mm[1][2] * mm[2][1])
                - mm[0][1] * (mm[1][0] * mm[2][2] - mm[1][2] * mm[2][0])
                + mm[0][2] * (mm[1][0] * mm[2][1] - mm[1][1] * mm[2][0])
        }
        return [detCol(0) / det, detCol(1) / det, detCol(2) / det]
    }

    @inline(__always) static func dist(_ a: Pt, _ b: Pt) -> Double {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }

    static func polylineLength(_ pts: [Pt]) -> Double {
        var s = 0.0
        for i in 1..<pts.count { s += dist(pts[i], pts[i - 1]) }
        return s
    }

    static func perpDist(_ p: Pt, _ a: Pt, _ b: Pt) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len = (dx * dx + dy * dy).squareRoot()
        if len < 1e-9 { return dist(p, a) }
        return abs((p.x - a.x) * dy - (p.y - a.y) * dx) / len
    }

    static func normalize(_ v: Pt) -> Pt {
        let l = (v.x * v.x + v.y * v.y).squareRoot()
        return l < 1e-12 ? Pt(0, 0) : Pt(v.x / l, v.y / l)
    }

    static func angleBetween(_ a: Pt, _ b: Pt) -> Double {
        let dot = a.x * b.x + a.y * b.y
        let cross = a.x * b.y - a.y * b.x
        return atan2(cross, dot)
    }

    /// Swept angle from `sa` to `ea`, in [0, 2π). `clockwise` means the
    /// increasing-atan2-angle direction (screen-clockwise in y-down space).
    static func arcSweep(_ sa: Double, _ ea: Double, clockwise: Bool) -> Double {
        var d = clockwise ? ea - sa : sa - ea
        while d < 0 { d += 2 * .pi }
        while d >= 2 * .pi { d -= 2 * .pi }
        return d
    }

    static func bernstein(_ u: Double) -> (Double, Double, Double, Double) {
        let t = 1 - u
        return (t * t * t, 3 * u * t * t, 3 * u * u * t, u * u * u)
    }

    static func bezierAt(_ q: [Pt], _ t: Double) -> Pt {
        let b = bernstein(t)
        return Pt(
            q[0].x * b.0 + q[1].x * b.1 + q[2].x * b.2 + q[3].x * b.3,
            q[0].y * b.0 + q[1].y * b.1 + q[2].y * b.2 + q[3].y * b.3)
    }

    static func bezier2At(_ q: [Pt], _ t: Double) -> Pt {
        let s = 1 - t
        return Pt(
            q[0].x * s * s + q[1].x * 2 * s * t + q[2].x * t * t,
            q[0].y * s * s + q[1].y * 2 * s * t + q[2].y * t * t)
    }

    static func bezier1At(_ q: [Pt], _ t: Double) -> Pt {
        Pt(q[0].x * (1 - t) + q[1].x * t, q[0].y * (1 - t) + q[1].y * t)
    }
}
