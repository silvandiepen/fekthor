import Foundation

/// Strokes (centreline) conversion mode.
///
/// Threshold to a foreground mask, thin to a 1px skeleton, trace the skeleton
/// into ordered graph edges, estimate a robust constant stroke width, and emit
/// adjustable stroke paths (D-008/D-014). Real strokes, never outlines.
/// Where stroke lines come from.
public enum StrokeSource: String, Sendable {
    /// Auto: centreline for line art, region edges for colour images.
    case auto
    /// Centreline of dark ink strokes (line art).
    case centreline
    /// Boundaries between colour regions (coloring-plate outlines).
    case edges
}

public struct StrokesConfig {
    public var threshold: UInt8
    public var epsilon: Double
    public var minLength: Int
    /// If set, overrides the estimated stroke width (the "adjustable" control):
    /// forces all strokes to one value.
    public var widthOverride: Double?
    /// When true (and no manual override), every stroke shares the median width
    /// across strokes instead of its own dt-estimated per-stroke width.
    public var uniformWidth: Bool
    public var source: StrokeSource
    public var colors: Int
    /// Curve smoothing strength for refined centrelines (0 polygonal … 1 full).
    public var smoothing: Double
    /// Straighten strength (0…1): greedier line fitting for near-straight runs.
    public var straighten: Double
    /// End-cap style for emitted strokes.
    public var cap: LineCap
    /// Opt-in taper (default off): a monotonically-narrowing tail becomes an
    /// outline fill; the body stays a real stroke.
    public var taper: Bool
    /// Optional line-colour override for the coloring plate (region edges).
    public var lineColor: RGB?
    public init(
        threshold: UInt8 = 128, epsilon: Double = 1.5, minLength: Int = 2,
        widthOverride: Double? = nil, uniformWidth: Bool = false,
        source: StrokeSource = .auto, colors: Int = 12,
        smoothing: Double = 1.0, straighten: Double = 0.5, cap: LineCap = .round,
        taper: Bool = false, lineColor: RGB? = nil
    ) {
        self.threshold = threshold
        self.epsilon = epsilon
        self.minLength = minLength
        self.widthOverride = widthOverride
        self.uniformWidth = uniformWidth
        self.source = source
        self.colors = colors
        self.smoothing = smoothing
        self.straighten = straighten
        self.cap = cap
        self.taper = taper
        self.lineColor = lineColor
    }
}

public enum StrokesMode {
    /// A greyscale, ≤2-colour image is treated as line art (use the centreline).
    static func isLineArt(_ img: RasterImage) -> Bool {
        let q = ColorQuantizer.quantizeAuto(img, maxColors: 6, minFraction: 0.02)
        guard q.palette.count <= 2 else { return false }
        return q.palette.allSatisfy { c in
            let mx = max(c.r, max(c.g, c.b))
            let mn = min(c.r, min(c.g, c.b))
            return Int(mx) - Int(mn) < 40
        }
    }

    /// Representative fill colour for a solid component (snaps grey → black).
    static func fillColor(_ img: RasterImage, _ labels: [Int], _ label: Int, _ w: Int) -> RGB {
        for p in 0..<labels.count where labels[p] == label {
            return sampleColor(img, Pt(Double(p % w), Double(p / w)))
        }
        return (0, 0, 0)
    }

    public static func run(_ img: RasterImage, config: StrokesConfig = StrokesConfig())
        -> VectorDocument
    {
        let useEdges: Bool
        switch config.source {
        case .centreline: useEdges = false
        case .edges: useEdges = true
        case .auto: useEdges = !isLineArt(img)
        }
        return useEdges ? runEdges(img, config: config) : runCentreline(img, config: config)
    }

    /// Coloring-plate lines: trace the boundaries between colour regions.
    static func runEdges(_ img: RasterImage, config: StrokesConfig) -> VectorDocument {
        let q = ColorQuantizer.quantizeAuto(
            img, maxColors: max(2, config.colors), minFraction: 0.004)
        // Light merge to drop noise regions before tracing boundaries.
        let s = 0.2
        let minArea = Int(Double(img.width * img.height) * 0.0006 * s)
        let (labels, _) = ComponentMerge.merge(
            indices: q.indices, palette: q.palette, width: img.width, height: img.height,
            minArea: minArea, colorThreshold: 40.0 * 40.0 * s)
        let chains = PlanarMap.boundaryChains(
            labels: labels, width: img.width, height: img.height, epsilon: max(1.0, config.epsilon))
        let width = config.widthOverride ?? 2.0
        let minLen = max(3.0, width * 1.5)
        let lineColor = config.lineColor ?? (0, 0, 0)

        var doc = VectorDocument(width: img.width, height: img.height)
        var nextID = 0
        let refineOpt = RefineOptions(
            tolerance: config.epsilon * 1.6, cornerAngle: 32, straighten: config.straighten,
            smoothing: config.smoothing)

        // Keep only chains long enough to matter, then order longest-first so the
        // double-line suppressor always keeps the longer of a parallel pair. The
        // sort has a deterministic tie-breaker (start point, then length) — equal
        // lengths must not reorder run to run (invariant #1).
        var kept: [(chain: [Pt], closed: Bool, len: Double)] = []
        for chain in chains where chain.count >= 2 {
            let first = chain.first!
            let last = chain.last!
            let closed =
                chain.count > 3
                && (pow(first.x - last.x, 2) + pow(first.y - last.y, 2)) < 4.0
            let len = polyLen(chain)
            if !closed && Double(chain.count) < minLen { continue }
            kept.append((chain, closed, len))
        }
        kept.sort {
            if $0.len != $1.len { return $0.len > $1.len }
            if $0.chain[0].x != $1.chain[0].x { return $0.chain[0].x < $1.chain[0].x }
            if $0.chain[0].y != $1.chain[0].y { return $0.chain[0].y < $1.chain[0].y }
            return $0.chain.count < $1.chain.count
        }

        // Grid-hash of emitted points for the O(n) parallel-double-line test: a
        // 1-px double line appears when two region boundaries run closer than the
        // line width. Drop a chain if ≥80% of its (densely resampled) points lie
        // within 0.8×width of an already-emitted longer chain.
        let proximity = max(0.8, 0.8 * width)
        var grid = PointGrid(cell: proximity)
        for item in kept {
            let dense = densify(item.chain, spacing: max(1.0, proximity * 0.5))
            var near = 0
            for p in dense where grid.hasNeighbor(p, within: proximity) { near += 1 }
            if !dense.isEmpty && Double(near) / Double(dense.count) >= 0.8 { continue }

            let refined = PathRefine.refine(item.chain, closed: item.closed, options: refineOpt)
            doc.elements.append(
                .stroke(
                    StrokePath(
                        id: "stroke-\(nextID)", color: lineColor, width: width,
                        closed: item.closed, points: item.chain, cap: config.cap, refined: refined)))
            nextID += 1
            for p in dense { grid.insert(p) }
        }
        return doc
    }

    /// Resample a polyline to at most `spacing`-apart points (for proximity tests).
    static func densify(_ pts: [Pt], spacing: Double) -> [Pt] {
        guard pts.count >= 2, spacing > 1e-6 else { return pts }
        var out: [Pt] = [pts[0]]
        for i in 1..<pts.count {
            let a = pts[i - 1]
            let b = pts[i]
            let d = (pow(b.x - a.x, 2) + pow(b.y - a.y, 2)).squareRoot()
            let steps = max(1, Int((d / spacing).rounded(.up)))
            for s in 1...steps {
                let t = Double(s) / Double(steps)
                out.append(Pt(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t))
            }
        }
        return out
    }
    /// Sample a representative ink colour from the source under a skeleton point.
    /// Near-grey dark ink is snapped to pure black so B&W line art gets clean
    /// black lines instead of muddy near-blacks.
    static func sampleColor(_ img: RasterImage, _ p: Pt) -> RGB {
        let x = min(max(Int(p.x), 0), img.width - 1)
        let y = min(max(Int(p.y), 0), img.height - 1)
        let px = img.pixel(x, y)
        let r = Int(px.0), g = Int(px.1), b = Int(px.2)
        let spread = max(r, max(g, b)) - min(r, min(g, b))
        if spread < 28 && max(r, max(g, b)) < 128 {
            return (0, 0, 0)
        }
        return (px.0, px.1, px.2)
    }

    static func runCentreline(_ img: RasterImage, config: StrokesConfig) -> VectorDocument {
        let w = img.width
        let h = img.height
        let n = w * h
        let mask = Foreground.dark(img, threshold: config.threshold)
        let fgCount = mask.count
        var skel = Skeleton.thin(mask)
        let skelCount = max(1, skel.count)
        // Area / skeleton-length approximates the *mean* constant stroke width;
        // used as the classifier reference and per-stroke fallback only.
        let globalWidth = config.widthOverride ?? max(1.0, Double(fgCount) / Double(skelCount))

        // Exact Euclidean distance transform, computed once and shared by width
        // estimation (2×dt ≈ local width) and per-branch spur pruning (below).
        let dt = DistanceTransform.toBackground(mask)

        var doc = VectorDocument(width: w, height: h)
        var nextID = 0
        let refineOpt = RefineOptions(
            tolerance: config.epsilon * 1.6, cornerAngle: 32, straighten: config.straighten,
            smoothing: config.smoothing)
        let fillRefineOpt = RefineOptions(
            tolerance: max(1.0, config.epsilon), cornerAngle: 32, straighten: config.straighten,
            smoothing: config.smoothing)

        // Hybrid: a solid blob (a dot/pupil) skeletonises to nothing, so classify
        // foreground components and emit solid ones as filled shapes; thin lines
        // stay as centreline strokes. The dt max within a component is a robust,
        // resample-independent blob signal: a filled blob's inradius (max dt) far
        // exceeds a stroke's half-width, where the old area/skeleton-length ratio
        // flipped between the `process` and eval resamples (plan 03 fix).
        var comp = [Int](repeating: -1, count: n)
        var compArea: [Int] = []
        var compSkel: [Int] = []
        var compMaxDt: [Double] = []
        let offs = [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, -1), (-1, 1), (1, 1)]
        var stack: [Int] = []
        for start in 0..<n where mask.fg[start] && comp[start] < 0 {
            let id = compArea.count
            compArea.append(0)
            compSkel.append(0)
            compMaxDt.append(0)
            comp[start] = id
            stack.append(start)
            while let p = stack.popLast() {
                compArea[id] += 1
                if skel.fg[p] { compSkel[id] += 1 }
                if dt[p] > compMaxDt[id] { compMaxDt[id] = dt[p] }
                let x = p % w
                let y = p / w
                for (dx, dy) in offs {
                    let nx = x + dx
                    let ny = y + dy
                    if nx >= 0, ny >= 0, nx < w, ny < h {
                        let q = ny * w + nx
                        if mask.fg[q] && comp[q] < 0 {
                            comp[q] = id
                            stack.append(q)
                        }
                    }
                }
            }
        }
        let halfGlobal = globalWidth / 2
        var solidLabel = [Int](repeating: 0, count: compArea.count)
        var solidCount = 0
        for c in 0..<compArea.count {
            let a = Double(compArea[c])
            let s = Double(max(1, compSkel[c]))
            // Blob signal: inradius (max dt) ≫ the mean stroke half-width, with a
            // minimum absolute inradius so genuine thin lines never qualify. Kept
            // alongside the area ratio so a thick short outline is not mislabelled.
            let dtBlob = compMaxDt[c] >= max(2.0, halfGlobal * 1.8) && a > s * globalWidth * 2.2
            let areaBlob = a > s * globalWidth * 2.6 && a > globalWidth * globalWidth * 2.5
            if dtBlob || areaBlob {
                solidCount += 1
                solidLabel[c] = solidCount
            }
        }
        if solidCount > 0 {
            var labels = [Int](repeating: 0, count: n)
            for p in 0..<n where mask.fg[p] {
                let sl = solidLabel[comp[p]]
                if sl > 0 {
                    labels[p] = sl
                    skel.fg[p] = false  // don't also trace it as a stroke
                }
            }
            // Solid blobs (dots, pupils) refine to typed rings; round ones become
            // circle/ellipse primitives (plan 02 acceptance: line-art eyes).
            let faces = PlanarMap.faces(
                labels: labels, width: w, height: h, epsilon: max(1.0, config.epsilon),
                refine: fillRefineOpt)
            for face in faces where face.label != 0 {
                // Blob eyes/dots are hand-drawn and irregular; a looser primitive
                // tolerance lets them become clean circle/ellipse primitives.
                guard let geometry = ShapeGeometryBuilder.build(
                    face: face, tolerance: max(1.0, config.epsilon), straighten: config.straighten,
                    detectPrimitives: true, primitiveTolerance: max(1.0, config.epsilon) * 5)
                else { continue }
                doc.elements.append(
                    .fill(
                        FillShape(
                            id: "fill-\(nextID)", color: fillColor(img, labels, face.label, w),
                            geometry: geometry)))
                nextID += 1
            }
        }

        // Skeleton junction distance (degree ≥ 3 pixels): width samples within
        // 1.5×localWidth of a junction sit in an inflated blob and are excluded.
        let junctionMask = skeletonJunctions(skel)
        let junctionDist = DistanceTransform.distance(fromSeeds: junctionMask, width: w, height: h)
        @inline(__always) func deg(_ p: Pt) -> Int {
            skeletonDegree(skel, Int(p.x.rounded()), Int(p.y.rounded()))
        }

        // Trace the remaining thin skeleton into strokes; merge through junctions.
        let rawEdges = SkeletonGraph.edges(skel)
        let edges = SkeletonGraph.mergeByTangent(rawEdges)

        // First pass: build each stroke's geometry and per-stroke width.
        struct Pending {
            var chain: [Pt]
            var closed: Bool
            var refined: RefinedPath
            var width: Double
            var color: RGB
        }
        var pendings: [Pending] = []
        for edge in edges {
            guard edge.count >= 2 else { continue }
            let first = edge.first!
            let last = edge.last!
            let closed =
                edge.count > 3
                && (pow(first.x - last.x, 2) + pow(first.y - last.y, 2)) < 4.0

            // Per-stroke width from dt (median of 2×dt away from junctions).
            let strokeWidth =
                config.widthOverride
                ?? medianChainWidth(
                    edge, dt: dt, junctionDist: junctionDist, w: w, h: h, fallback: globalWidth)

            // Per-branch spur pruning: use this stroke's own width as the length
            // scale, so a thin decorative branch is not pruned by the width of the
            // thick outlines it neighbours.
            let spurLen = max(6.0, strokeWidth * 2.0)
            if !closed && polyLen(edge) < spurLen { continue }

            // Endpoint quality (open chains): extend free tips to the drawn visual
            // tip (mask march ≤1.5×w) and close small T-joint gaps to a neighbouring
            // centreline (skeleton march ≤1.2×w). Junction ends keep the exact node
            // pixel so meeting strokes share it (snap invariant). Done on the dense
            // chain before refinement.
            var dense = edge
            if !closed {
                dense = extendEndpoints(
                    edge, mask: mask, skel: skel, width: strokeWidth, w: w, h: h,
                    degStart: deg(first), degEnd: deg(last))
            }
            let smoothed =
                closed ? dense : Geometry.smoothPolyline(dense, window: 2, iterations: 2)
            let refined = PathRefine.refine(smoothed, closed: closed, options: refineOpt)
            if refined.segments.count < 1 { continue }
            let color = sampleColor(img, edge[edge.count / 2])
            pendings.append(
                Pending(
                    chain: smoothed, closed: closed, refined: refined, width: strokeWidth,
                    color: color))
        }

        // Uniform width: replace every stroke's width with the median across
        // strokes (a manual override already forced them all equal above).
        if config.uniformWidth && config.widthOverride == nil && !pendings.isEmpty {
            let med = median(pendings.map { $0.width })
            for i in pendings.indices { pendings[i].width = med }
        }

        for p in pendings {
            let simplified =
                p.closed
                ? Geometry.simplifyClosed(p.chain, epsilon: config.epsilon)
                : Geometry.simplifyOpen(p.chain, epsilon: config.epsilon)
            // Optional taper: a monotonically-narrowing tail becomes an outline fill
            // while the body stays a real stroke (default off — editability first).
            if config.taper && !p.closed,
                let taperResult = TaperBuilder.build(
                    chain: p.chain, dt: dt, medianWidth: p.width, w: w, h: h, options: refineOpt)
            {
                if let bodyRefined = taperResult.body {
                    doc.elements.append(
                        .stroke(
                            StrokePath(
                                id: "stroke-\(nextID)", color: p.color, width: p.width,
                                closed: false, points: simplified, cap: config.cap,
                                refined: bodyRefined)))
                    nextID += 1
                }
                for tail in taperResult.tails {
                    doc.elements.append(
                        .fill(
                            FillShape(
                                id: "fill-\(nextID)", color: p.color, geometry: .refined([tail]))))
                    nextID += 1
                }
                continue
            }
            doc.elements.append(
                .stroke(
                    StrokePath(
                        id: "stroke-\(nextID)", color: p.color, width: p.width, closed: p.closed,
                        points: simplified, cap: config.cap, refined: p.refined)))
            nextID += 1
        }
        return doc
    }

    // MARK: - Width / geometry helpers

    /// Median of a value list (deterministic; lower-middle for even counts).
    static func median(_ values: [Double]) -> Double {
        if values.isEmpty { return 0 }
        let s = values.sorted()
        return s[(s.count - 1) / 2]
    }

    static func polyLen(_ pts: [Pt]) -> Double {
        var s = 0.0
        for i in 1..<pts.count {
            s += (pow(pts[i].x - pts[i - 1].x, 2) + pow(pts[i].y - pts[i - 1].y, 2)).squareRoot()
        }
        return s
    }

    /// Median local width (2×dt) sampled along a chain, excluding points within
    /// 1.5×localWidth of a junction (junction blobs inflate dt). Falls back to all
    /// samples if the exclusion removes nearly everything (a short chain hugging a
    /// junction), and to `fallback` if the chain is degenerate.
    static func medianChainWidth(
        _ chain: [Pt], dt: [Double], junctionDist: [Double], w: Int, h: Int, fallback: Double
    ) -> Double {
        var kept: [Double] = []
        var all: [Double] = []
        for p in chain {
            let xi = min(max(Int(p.x.rounded()), 0), w - 1)
            let yi = min(max(Int(p.y.rounded()), 0), h - 1)
            let idx = yi * w + xi
            let lw = 2 * dt[idx]
            all.append(lw)
            if junctionDist[idx] >= 1.5 * lw { kept.append(lw) }
        }
        let src = kept.count >= 3 ? kept : all
        if src.isEmpty { return fallback }
        return max(1.0, median(src))
    }

    /// Extend the open ends of a dense centreline chain. Each free tip (skeleton
    /// degree 1) is marched along its outgoing tangent: to the drawn visual tip
    /// while the foreground mask continues (≤1.5×width), and — closing a small gap
    /// — to a neighbouring centreline the tangent hits (≤1.2×width). The farther of
    /// the two is used. Junction ends (degree ≥ 3) are left on their exact node
    /// pixel so strokes meeting there stay point-identical.
    static func extendEndpoints(
        _ chain: [Pt], mask: Mask, skel: Mask, width: Double, w: Int, h: Int,
        degStart: Int, degEnd: Int
    ) -> [Pt] {
        var pts = chain
        let n = pts.count
        guard n >= 2 else { return pts }
        func tangent(at endIdx: Int, innerIdx: Int) -> Pt {
            let e = pts[endIdx]
            let i = pts[innerIdx]
            let dx = e.x - i.x
            let dy = e.y - i.y
            let m = (dx * dx + dy * dy).squareRoot()
            return m < 1e-9 ? Pt(0, 0) : Pt(dx / m, dy / m)
        }
        func march(_ end: Pt, _ t: Pt) -> Pt? {
            if t.x == 0 && t.y == 0 { return nil }
            let maxTip = 1.5 * width
            let maxT = 1.2 * width
            let maxDist = max(maxTip, maxT)
            var tipD = 0.0
            var maskBroken = false
            var firstTHit = 0.0
            var d = 0.5
            while d <= maxDist {
                let px = end.x + t.x * d
                let py = end.y + t.y * d
                let xi = Int(px.rounded())
                let yi = Int(py.rounded())
                if xi < 0 || yi < 0 || xi >= w || yi >= h { break }
                let idx = yi * w + xi
                if !maskBroken && d <= maxTip {
                    if mask.fg[idx] { tipD = d } else { maskBroken = true }
                }
                if firstTHit == 0 && d >= max(1.0, width * 0.5) && d <= maxT && skel.fg[idx] {
                    firstTHit = d
                }
                d += 0.5
            }
            let ext = max(tipD, firstTHit)
            return ext > 0.5 ? Pt(end.x + t.x * ext, end.y + t.y * ext) : nil
        }
        if degStart == 1 {
            let inner = min(4, n - 1)
            if let p = march(pts[0], tangent(at: 0, innerIdx: inner)) { pts.insert(p, at: 0) }
        }
        if degEnd == 1 {
            let inner = max(0, n - 1 - 4)
            if let p = march(pts[n - 1], tangent(at: n - 1, innerIdx: inner)) { pts.append(p) }
        }
        return pts
    }

    /// Skeleton pixels with degree ≥ 3 (junctions) as a seed mask.
    static func skeletonJunctions(_ skel: Mask) -> [Bool] {
        let w = skel.width
        let h = skel.height
        var out = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 0..<w where skel.fg[y * w + x] {
                if skeletonDegree(skel, x, y) >= 3 { out[y * w + x] = true }
            }
        }
        return out
    }

    /// Count of 8-connected skeleton neighbours of a pixel.
    @inline(__always)
    static func skeletonDegree(_ skel: Mask, _ x: Int, _ y: Int) -> Int {
        var c = 0
        for dy in -1...1 {
            for dx in -1...1 where !(dx == 0 && dy == 0) {
                if skel.at(x + dx, y + dy) { c += 1 }
            }
        }
        return c
    }
}

/// A coarse uniform spatial hash for O(1)-ish "is any stored point within r?"
/// queries (used by the coloring-plate double-line suppressor). The dictionary is
/// only queried, never iterated into output, so ordering does not affect results.
struct PointGrid {
    let cell: Double
    private var buckets: [Int64: [Pt]] = [:]

    init(cell: Double) { self.cell = max(0.5, cell) }

    @inline(__always) private func key(_ cx: Int, _ cy: Int) -> Int64 {
        (Int64(cx) << 32) ^ (Int64(cy) & 0xffff_ffff)
    }

    mutating func insert(_ p: Pt) {
        let cx = Int((p.x / cell).rounded(.down))
        let cy = Int((p.y / cell).rounded(.down))
        buckets[key(cx, cy), default: []].append(p)
    }

    func hasNeighbor(_ p: Pt, within r: Double) -> Bool {
        let cx = Int((p.x / cell).rounded(.down))
        let cy = Int((p.y / cell).rounded(.down))
        let r2 = r * r
        for dy in -1...1 {
            for dx in -1...1 {
                guard let pts = buckets[key(cx + dx, cy + dy)] else { continue }
                for q in pts {
                    if (p.x - q.x) * (p.x - q.x) + (p.y - q.y) * (p.y - q.y) <= r2 { return true }
                }
            }
        }
        return false
    }
}
