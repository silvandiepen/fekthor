import Foundation

/// A mode-aware quality score for a conversion.
///
/// Unlike raw pixel metrics (which are meaningless for Strokes and never exact
/// for Gradient), this scores each mode with the lens that matches its intent,
/// so the numbers are comparable *across* modes for the same source (which Auto
/// mode, plan 06, relies on). Measurement only — computing a score never changes
/// conversion behaviour.
public struct QualityScore: Codable, Sendable {
    /// 0…1, mode-aware reconstruction fidelity (see `Quality.score`).
    public var fidelity: Double
    /// 0…1, from node/path counts (fewer, cleaner paths score higher).
    public var simplicity: Double
    /// 0…1, `0.75*fidelity + 0.25*simplicity`.
    public var overall: Double
    /// Raw sub-metrics (pixel, edge, chamfer, psnr, nodes, …) for diagnostics
    /// and later tuning without recomputation.
    public var detail: [String: Double]

    public init(fidelity: Double, simplicity: Double, overall: Double, detail: [String: Double]) {
        self.fidelity = fidelity
        self.simplicity = simplicity
        self.overall = overall
        self.detail = detail
    }
}

public enum Quality {
    // MARK: Public API

    /// Score a conversion. `rendered` is the `Rasterizer.render` output at working
    /// size (must match `source` dimensions).
    public static func score(
        source: RasterImage, document: VectorDocument, rendered: RasterImage, mode: Mode
    ) -> QualityScore {
        var detail: [String: Double] = [:]
        let fidelity: Double
        switch mode {
        case .shapes: fidelity = shapesFidelity(source, rendered, &detail)
        case .strokes: fidelity = strokesFidelity(source, rendered, &detail)
        case .gradient: fidelity = gradientFidelity(source, rendered, &detail)
        }
        let simplicity = simplicityScore(document, &detail)
        let overall = clamp01(0.75 * fidelity + 0.25 * simplicity)
        detail["fidelity"] = fidelity
        detail["simplicity"] = simplicity
        detail["overall"] = overall
        return QualityScore(
            fidelity: fidelity, simplicity: simplicity, overall: overall, detail: detail)
    }

    // MARK: Per-mode fidelity

    /// Shapes: half exact-pixel match, half edge alignment (crisp shared borders).
    static func shapesFidelity(
        _ source: RasterImage, _ rendered: RasterImage, _ detail: inout [String: Double]
    ) -> Double {
        let pixel = Comparer.compare(source, rendered, tolerance: 8).exactPct / 100.0
        let srcEdge = sobelEdgeMap(source, threshold: 48)
        let outEdge = sobelEdgeMap(rendered, threshold: 48)
        let chamfer = symmetricChamfer(srcEdge, outEdge, width: source.width, height: source.height)
        let edge = 1 - clamp(chamfer / 4, 0, 1)
        detail["pixel"] = pixel
        detail["edge"] = edge
        detail["chamfer"] = chamfer
        return clamp01(0.5 * pixel + 0.5 * edge)
    }

    /// Strokes: pixel metrics on a colour source are meaningless, so compare line
    /// masks. Line-art sources compare dark ink; colour sources compare edges
    /// (the coloring-plate output should trace them).
    static func strokesFidelity(
        _ source: RasterImage, _ rendered: RasterImage, _ detail: inout [String: Double]
    ) -> Double {
        let lineArt = StrokesMode.isLineArt(source)
        let srcMask: [Bool] =
            lineArt
            ? Foreground.dark(source, threshold: 128).fg
            : sobelEdgeMap(source, threshold: 48)
        let outMask = darkMask(rendered, threshold: 128)
        let chamfer = symmetricChamfer(
            srcMask, outMask, width: source.width, height: source.height)
        detail["chamfer"] = chamfer
        detail["lineArt"] = lineArt ? 1 : 0
        return clamp01(1 - clamp(chamfer / 6, 0, 1))
    }

    /// Gradient: never matches exactly, so PSNR is the right lens (plus a light
    /// exact-pixel term at a looser tolerance).
    static func gradientFidelity(
        _ source: RasterImage, _ rendered: RasterImage, _ detail: inout [String: Double]
    ) -> Double {
        let m = Comparer.compare(source, rendered, tolerance: 12)
        let pixel = m.exactPct / 100.0
        let psnr = m.psnr.isFinite ? m.psnr : 99.0
        let psnrTerm = clamp((psnr - 18) / 18, 0, 1)
        detail["pixel"] = pixel
        detail["psnr"] = psnr
        detail["psnrTerm"] = psnrTerm
        return clamp01(0.35 * pixel + 0.65 * psnrTerm)
    }

    // MARK: Simplicity

    static func simplicityScore(_ document: VectorDocument, _ detail: inout [String: Double])
        -> Double
    {
        let nodes = Double(document.nodeCount)
        let paths = Double(document.elements.count)
        let nodeTerm = 1 - clamp(log10(max(nodes, 10) / 10) / 3, 0, 1)
        let pathFactor = 1 - clamp(paths / 400, 0, 0.3)
        detail["nodes"] = nodes
        detail["paths"] = paths
        return clamp01(nodeTerm * pathFactor)
    }

    // MARK: Edge maps

    /// Sobel gradient-magnitude edge map on luminance; `true` where magnitude
    /// exceeds `threshold`. Borders are non-edges (no wrap). O(n).
    static func sobelEdgeMap(_ img: RasterImage, threshold: Double) -> [Bool] {
        let w = img.width
        let h = img.height
        let n = w * h
        var lum = [Double](repeating: 0, count: n)
        img.data.withUnsafeBufferPointer { p in
            for i in 0..<n {
                let o = i * 4
                lum[i] = Foreground.luminance(p[o], p[o + 1], p[o + 2])
            }
        }
        var edge = [Bool](repeating: false, count: n)
        if w < 3 || h < 3 { return edge }
        lum.withUnsafeBufferPointer { l in
            for y in 1..<(h - 1) {
                let r0 = (y - 1) * w
                let r1 = y * w
                let r2 = (y + 1) * w
                for x in 1..<(w - 1) {
                    let tl = l[r0 + x - 1], tc = l[r0 + x], tr = l[r0 + x + 1]
                    let ml = l[r1 + x - 1], mr = l[r1 + x + 1]
                    let bl = l[r2 + x - 1], bc = l[r2 + x], br = l[r2 + x + 1]
                    let gx = (tr + 2 * mr + br) - (tl + 2 * ml + bl)
                    let gy = (bl + 2 * bc + br) - (tl + 2 * tc + tr)
                    if (gx * gx + gy * gy).squareRoot() > threshold { edge[r1 + x] = true }
                }
            }
        }
        return edge
    }

    /// Dark pixels of an (opaque) rendered raster: luminance below `threshold`.
    static func darkMask(_ img: RasterImage, threshold: Double) -> [Bool] {
        let n = img.width * img.height
        var m = [Bool](repeating: false, count: n)
        img.data.withUnsafeBufferPointer { p in
            for i in 0..<n {
                let o = i * 4
                m[i] = Foreground.luminance(p[o], p[o + 1], p[o + 2]) < threshold
            }
        }
        return m
    }

    // MARK: Chamfer distance transform

    /// Two-pass 3-4 chamfer distance transform: for each pixel, the approximate
    /// Euclidean distance (in px) to the nearest `true` cell in `mask`. O(n) — no
    /// per-pixel nearest search. Cells with no reachable feature get `.infinity`.
    static func distanceTransform(_ mask: [Bool], width w: Int, height h: Int) -> [Double] {
        let big = Double(3 * (w + h) + 10)  // larger than any reachable 3-4 distance
        var d = [Double](repeating: big, count: w * h)
        for i in 0..<mask.count where mask[i] { d[i] = 0 }
        d.withUnsafeMutableBufferPointer { dp in
            // Forward pass: top-left → bottom-right.
            for y in 0..<h {
                let r = y * w
                for x in 0..<w {
                    let i = r + x
                    var v = dp[i]
                    if x > 0 { v = min(v, dp[i - 1] + 3) }
                    if y > 0 {
                        v = min(v, dp[i - w] + 3)
                        if x > 0 { v = min(v, dp[i - w - 1] + 4) }
                        if x < w - 1 { v = min(v, dp[i - w + 1] + 4) }
                    }
                    dp[i] = v
                }
            }
            // Backward pass: bottom-right → top-left.
            for y in stride(from: h - 1, through: 0, by: -1) {
                let r = y * w
                for x in stride(from: w - 1, through: 0, by: -1) {
                    let i = r + x
                    var v = dp[i]
                    if x < w - 1 { v = min(v, dp[i + 1] + 3) }
                    if y < h - 1 {
                        v = min(v, dp[i + w] + 3)
                        if x < w - 1 { v = min(v, dp[i + w + 1] + 4) }
                        if x > 0 { v = min(v, dp[i + w - 1] + 4) }
                    }
                    dp[i] = v
                }
            }
        }
        // 3-4 units approximate 3× the Euclidean distance; normalise to px.
        for i in 0..<d.count { d[i] = d[i] >= big ? .infinity : d[i] / 3 }
        return d
    }

    /// Symmetric mean chamfer distance (px) between two binary masks: the mean,
    /// over each mask's set pixels, of the distance to the nearest set pixel in
    /// the other, averaged in both directions. If either mask is empty the two
    /// are maximally dissimilar → a large distance so fidelity floors out.
    static func symmetricChamfer(_ a: [Bool], _ b: [Bool], width w: Int, height h: Int) -> Double {
        let ca = countTrue(a)
        let cb = countTrue(b)
        if ca == 0 && cb == 0 { return 0 }  // both empty: nothing to disagree about
        // One-sided emptiness is a total mismatch; report a saturating distance.
        let saturate = Double(w + h)
        if ca == 0 || cb == 0 { return saturate }
        let dtB = distanceTransform(b, width: w, height: h)
        let dtA = distanceTransform(a, width: w, height: h)
        let meanAtoB = meanOverMask(a, dtB, saturate)
        let meanBtoA = meanOverMask(b, dtA, saturate)
        return (meanAtoB + meanBtoA) / 2
    }

    private static func meanOverMask(_ mask: [Bool], _ dt: [Double], _ saturate: Double) -> Double {
        var sum = 0.0
        var count = 0
        for i in 0..<mask.count where mask[i] {
            let v = dt[i]
            sum += v.isFinite ? v : saturate
            count += 1
        }
        return count == 0 ? 0 : sum / Double(count)
    }

    private static func countTrue(_ m: [Bool]) -> Int {
        var c = 0
        for v in m where v { c += 1 }
        return c
    }

    // MARK: Clamping

    @inline(__always) static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(v, lo), hi)
    }
    @inline(__always) static func clamp01(_ v: Double) -> Double { clamp(v, 0, 1) }
}
