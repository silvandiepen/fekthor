import Foundation

/// Shapes (flat fill) conversion mode.
///
/// Colour-quantize the source, trace each colour region into filled contours,
/// simplify, and assemble a back-to-front filled document. No strokes (D-002).
public struct ShapesConfig {
    public var colors: Int
    public var iters: Int
    public var epsilon: Double
    /// 0 = keep every region; 1 = aggressively merge similar / small regions.
    public var simplicity: Double
    /// Auto-detect dominant colours (excludes anti-aliasing) vs fixed k-means.
    public var autoColors: Bool
    /// Curve smoothing strength for the refined cubics (0 polygonal … 1 full).
    public var smoothing: Double
    /// Straighten strength (0…1): greedier line fitting for near-straight runs.
    public var straighten: Double
    /// Minimum source fraction for auto-colour palette entries.
    public var autoColorMinFraction: Double
    /// Flatten strength (0…1): collapse shade families via the hue-weighted Oklab
    /// metric. 0 keeps the pipeline byte-identical to the non-flatten path.
    public var flatten: Double
    /// ML part awareness (Vision instance masks): regions never merge across a
    /// detected part boundary. Opt-in; output may vary across OS versions.
    public var partAware: Bool
    public init(
        colors: Int = 16, iters: Int = 8, epsilon: Double = 2.0, simplicity: Double = 0.3,
        autoColors: Bool = true, smoothing: Double = 0.65, straighten: Double = 0.5,
        autoColorMinFraction: Double = 0.004, flatten: Double = 0, partAware: Bool = false
    ) {
        self.colors = colors
        self.iters = iters
        self.epsilon = epsilon
        self.simplicity = simplicity
        self.autoColors = autoColors
        self.smoothing = smoothing
        self.straighten = straighten
        self.autoColorMinFraction = autoColorMinFraction
        self.flatten = flatten
        self.partAware = partAware
    }
}

public enum ShapesMode {
    public struct Output {
        public var document: VectorDocument
        public var detail: [String: Double]
    }

    /// Distinct-colour guard for family clustering (flatten-d² units): once every
    /// remaining palette pair is farther apart than this, clustering stops even if
    /// more than the Colours count remain. Sits above a typical shade family's
    /// spread but below distinct hues, so shades collapse while cape-red vs
    /// background-red, black eyes and tiny accents survive any Flatten value.
    static let flattenSeparation = 0.10

    /// Collapse region labels that share an identical colour into one label, so
    /// PlanarMap emits a single flat multi-region face per colour. Order follows
    /// first appearance in `colors` (deterministic — no dictionary order leaks).
    static func groupByColour(_ labels: [Int], _ colors: [RGB]) -> (labels: [Int], colors: [RGB]) {
        var keyToLabel: [Int: Int] = [:]
        var grouped: [RGB] = []
        var map = [Int](repeating: 0, count: colors.count)
        for (i, c) in colors.enumerated() {
            let key = Int(c.r) << 16 | Int(c.g) << 8 | Int(c.b)
            if let l = keyToLabel[key] {
                map[i] = l
            } else {
                let l = grouped.count
                keyToLabel[key] = l
                grouped.append(c)
                map[i] = l
            }
        }
        return (labels.map { map[$0] }, grouped)
    }

    public static func run(_ img: RasterImage, config: ShapesConfig = ShapesConfig())
        -> VectorDocument
    {
        runWithDetail(img, config: config).document
    }

    /// A region's colour comes from its OWN pixels — the per-channel median —
    /// not from a global palette bucket that anti-aliasing pollutes. The median
    /// is robust to the AA ring (a minority) and to resampling (which leaves few
    /// exactly-equal pixels, defeating a mode). Black eyes stay black.
    static func regionDominantColors(_ img: RasterImage, labels: [Int], fallback: [RGB]) -> [RGB] {
        let n = img.width * img.height
        guard labels.count == n, !fallback.isEmpty else { return fallback }
        let count = fallback.count
        var hist = [Int](repeating: 0, count: count * 3 * 256)
        var totals = [Int](repeating: 0, count: count)
        for i in 0..<n {
            let l = labels[i]
            if l < 0 || l >= count { continue }
            let o = i * 4
            let base = l * 768
            hist[base + Int(img.data[o])] += 1
            hist[base + 256 + Int(img.data[o + 1])] += 1
            hist[base + 512 + Int(img.data[o + 2])] += 1
            totals[l] += 1
        }
        var out = fallback
        for l in 0..<count where totals[l] > 0 {
            let half = (totals[l] + 1) / 2
            var channels = [UInt8](repeating: 0, count: 3)
            for c in 0..<3 {
                var acc = 0
                for v in 0..<256 {
                    acc += hist[l * 768 + c * 256 + v]
                    if acc >= half {
                        channels[c] = UInt8(v)
                        break
                    }
                }
            }
            out[l] = (channels[0], channels[1], channels[2])
        }
        return out
    }

    /// Absorb anti-aliasing bands: a *thin* region (area ≈ its boundary length ×
    /// a pixel or two) whose colour lies on the blend line between its two main
    /// neighbours is a resampling artefact, not content — merge it into the
    /// neighbour it borders most. Genuine thin content (shirt stripes) has its
    /// own non-blend colour and is untouched.
    static func absorbBlendBands(
        _ labels: [Int], colors: [RGB], width w: Int, height h: Int
    ) -> [Int] {
        let count = colors.count
        guard count > 2 else { return labels }
        var area = [Int](repeating: 0, count: count)
        var boundary = [[Int: Int]](repeating: [:], count: count)
        var perimeter = [Int](repeating: 0, count: count)
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                let a = labels[i]
                if a < 0 || a >= count { continue }
                area[a] += 1
                if x < w - 1 {
                    let b = labels[i + 1]
                    if b != a, b >= 0, b < count {
                        boundary[a][b, default: 0] += 1
                        boundary[b][a, default: 0] += 1
                        perimeter[a] += 1
                        perimeter[b] += 1
                    }
                }
                if y < h - 1 {
                    let b = labels[i + w]
                    if b != a, b >= 0, b < count {
                        boundary[a][b, default: 0] += 1
                        boundary[b][a, default: 0] += 1
                        perimeter[a] += 1
                        perimeter[b] += 1
                    }
                }
            }
        }
        var remap = Array(0..<count)
        for l in 0..<count where area[l] > 0 && perimeter[l] > 0 {
            let thinness = Double(area[l]) / (Double(perimeter[l]) / 2.0)
            if thinness > 1.9 { continue }
            // Two most-bordered neighbours (deterministic: count desc, label asc).
            let nbs = boundary[l].sorted {
                $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key
            }
            guard let first = nbs.first else { continue }
            let nbColors = nbs.prefix(2).map { colors[$0.key] }
            if ColorQuantizer.isBlend(colors[l], nbColors) {
                remap[l] = first.key
            }
        }
        // Resolve chains (band absorbed into band) deterministically.
        func resolve(_ l: Int) -> Int {
            var r = l
            var hops = 0
            while remap[r] != r && hops < count {
                r = remap[r]
                hops += 1
            }
            return r
        }
        if remap.enumerated().allSatisfy({ $0.offset == $0.element }) { return labels }
        return labels.map { $0 >= 0 && $0 < count ? resolve($0) : $0 }
    }

    public static func runWithDetail(_ img: RasterImage, config: ShapesConfig = ShapesConfig())
        -> Output
    {
        let alphaStats = AlphaLabels.stats(img)
        let flattenOn = config.flatten > 0
        // Flatten quantises *fine* first, then collapses shade families down to the
        // Colours count (never re-runs k-means at a lower k — that reintroduces RGB
        // mud). At flatten=0 the counts and path are unchanged (byte-identical).
        let fineColors = flattenOn ? 32 : max(2, config.colors)
        let qFine =
            config.autoColors
            ? AlphaLabels.quantize(
                img, maxColors: fineColors,
                minFraction: config.autoColorMinFraction, alphaStats: alphaStats,
                exactPalette: config.autoColorMinFraction <= 0.002)
            : ColorQuantizer.quantize(
                img, k: flattenOn ? 32 : config.colors, iters: config.iters)
        let q =
            flattenOn
            ? PaletteFamily.reduce(
                qFine, targetColors: max(2, config.colors), flatten: config.flatten,
                separation: ShapesMode.flattenSeparation)
            : qFine
        let transparentLabel = AlphaLabels.transparentLabel(
            paletteCount: q.palette.count, alphaStats: alphaStats)
        let quantized = AlphaLabels.withTransparentLabel(
            img, quantized: q, transparentLabel: transparentLabel)

        // ML part awareness (opt-in): Vision instance masks become merge walls.
        let walls: [Int]? = config.partAware ? SubjectMask.instanceLabels(img) : nil
        // Part-aware palette membership: a colour family living almost entirely
        // outside the subject (the background/cape red) must not appear inside
        // it — in-subject pixels of such families reassign to their nearest
        // in-subject family (a beard shadow stops rendering as background red).
        let quantized2 = walls.map { partitionPalette(quantized, walls: $0) } ?? quantized

        // Optionally merge similar / small regions for cleaner, simpler shapes.
        let labels: [Int]
        let colors: [RGB]
        if flattenOn {
            // Flatten region merging: touching shade bands collapse under the Oklab
            // flatten metric and every merged region takes its **dominant family
            // colour** (flat, never a blended mean). Merging stays per-component so
            // boundaries stay simple (already-flat art keeps its low node count and
            // its distinct large colours), while the distinct-colour guard keeps
            // small far-hued features (black eyes, a red accent) at any Flatten value.
            let s = min(1.0, max(0.0, config.simplicity))
            let minArea = Int(
                Double(img.width * img.height) * (0.0006 * s + 0.0006 * config.flatten))
            let colorThreshold = 0.006 + 0.012 * config.flatten
            let (rawLabels, rawColors) = ComponentMerge.merge(
                indices: quantized2.indices, palette: quantized2.palette,
                width: img.width, height: img.height, minArea: minArea,
                colorThreshold: colorThreshold, flatten: config.flatten,
                distinctGuard: ShapesMode.flattenSeparation, walls: walls)
            // Group same-colour regions into one flat face. ComponentMerge already
            // absorbed specks (so boundaries stay clean and node counts low); merging
            // the face *labels* by colour then keeps the fill count at ~the palette
            // size — a shaded source becomes a handful of flat fills, while already
            // flat art is unchanged (its regions were distinct colours anyway).
            (labels, colors) = ShapesMode.groupByColour(rawLabels, rawColors)
        } else if config.simplicity > 0 {
            let s = min(1.0, max(0.0, config.simplicity))
            let minArea = Int(Double(img.width * img.height) * 0.0006 * s)
            let colorThreshold = 40.0 * 40.0 * s
            (labels, colors) = ComponentMerge.merge(
                indices: quantized2.indices, palette: quantized2.palette, width: img.width, height: img.height,
                minArea: minArea, colorThreshold: colorThreshold, walls: walls)
        } else if walls != nil {
            // No merging requested, but part walls still require components to
            // be split at part boundaries.
            (labels, colors) = ComponentMerge.merge(
                indices: quantized2.indices, palette: quantized2.palette,
                width: img.width, height: img.height,
                minArea: 0, colorThreshold: 0, walls: walls)
        } else {
            labels = quantized2.indices
            colors = quantized2.palette
        }
        // Per-region colour re-estimation (flatten=0 path): a region's colour
        // comes from its OWN pixels — the dominant exact source RGB — not from a
        // global palette bucket that anti-aliasing pollutes. This is what keeps
        // black eyes black instead of the bucket's muddy brown, and it makes flat
        // art round-trip its true colours. Falls back to the palette colour when
        // no exact colour dominates (photographic regions).
        var finalLabels = labels
        var finalColors = colors
        if !flattenOn {
            finalLabels = absorbBlendBands(labels, colors: colors, width: img.width, height: img.height)
            finalColors = regionDominantColors(img, labels: finalLabels, fallback: colors)
        }
        let transparentOutputLabels = AlphaLabels.outputLabels(
            labels: finalLabels, indices: quantized2.indices, transparentLabel: transparentLabel)

        // Shared-edge planar map with geometry refinement: adjacent regions use
        // identical refined boundary chains (no gaps), corners stay sharp, and
        // near-straight runs / roundings become lines / arcs / cubics (plan 02).
        let refineOpt = RefineOptions(
            tolerance: config.epsilon * 1.8, cornerAngle: 32, straighten: config.straighten,
            smoothing: config.smoothing)
        let faces = PlanarMap.faces(
            labels: finalLabels, width: img.width, height: img.height, epsilon: config.epsilon,
            refine: refineOpt)

        var doc = VectorDocument(width: img.width, height: img.height)
        var nextID = 0
        for face in faces {
            if transparentOutputLabels.contains(face.label) { continue }
            let color = face.label < finalColors.count ? finalColors[face.label] : (0, 0, 0)
            guard let geometry = ShapeGeometryBuilder.build(
                face: face, tolerance: config.epsilon, straighten: config.straighten,
                detectPrimitives: true,
                primitiveTolerance: config.epsilon * (transparentLabel == nil ? 1.6 : 8.0))
            else { continue }
            doc.elements.append(
                .fill(FillShape(id: "fill-\(nextID)", color: color, geometry: geometry)))
            nextID += 1
        }
        return Output(
            document: doc,
            detail: [
                "paletteExact": Double(q.paletteExactCount),
                "backgroundTransparent": transparentLabel == nil ? 0 : 1,
            ])
    }
}

private enum AlphaLabels {
    static let sentinel: RGB = (255, 0, 255)

    static func stats(_ img: RasterImage) -> (meaningful: Bool, transparentCount: Int) {
        let n = img.width * img.height
        var low250 = 0
        var low128 = 0
        for i in 0..<n {
            let a = img.data[i * 4 + 3]
            if a < 250 { low250 += 1 }
            if a < 128 { low128 += 1 }
        }
        return (Double(low250) >= Double(n) * 0.02 && low128 > 0, low128)
    }

    static func transparentLabel(
        paletteCount: Int, alphaStats: (meaningful: Bool, transparentCount: Int)
    ) -> Int? {
        alphaStats.meaningful ? paletteCount : nil
    }

    static func quantize(
        _ img: RasterImage, maxColors: Int, minFraction: Double,
        alphaStats: (meaningful: Bool, transparentCount: Int), exactPalette: Bool
    ) -> Quantized {
        guard alphaStats.meaningful else {
            return ColorQuantizer.quantizeAuto(
                img, maxColors: maxColors, minFraction: minFraction, exactPalette: exactPalette)
        }
        let n = img.width * img.height
        let opaqueCount = max(1, n - alphaStats.transparentCount)
        var data: [UInt8] = []
        data.reserveCapacity(opaqueCount * 4)
        for i in 0..<n where img.data[i * 4 + 3] >= 128 {
            let o = i * 4
            data.append(img.data[o])
            data.append(img.data[o + 1])
            data.append(img.data[o + 2])
            data.append(255)
        }
        let colourImage = RasterImage(width: opaqueCount, height: 1, data: data)
        return ColorQuantizer.quantizeAuto(
            colourImage, maxColors: maxColors, minFraction: minFraction,
            exactPalette: exactPalette)
    }

    static func withTransparentLabel(
        _ img: RasterImage, quantized q: Quantized, transparentLabel: Int?
    ) -> Quantized {
        guard let transparentLabel else { return q }
        var palette = q.palette
        palette.append(sentinel)
        var indices = [Int](repeating: 0, count: img.width * img.height)
        var sourceIndex = 0
        for i in 0..<indices.count {
            if img.data[i * 4 + 3] < 128 {
                indices[i] = transparentLabel
            } else {
                indices[i] = q.indices[sourceIndex]
                sourceIndex += 1
            }
        }
        return Quantized(
            width: img.width, height: img.height, palette: palette, indices: indices,
            paletteExactCount: q.paletteExactCount)
    }

    static func outputLabels(labels: [Int], indices: [Int], transparentLabel: Int?) -> Set<Int> {
        guard let transparentLabel else { return [] }
        var out = Set<Int>()
        for i in 0..<labels.count where indices[i] == transparentLabel {
            out.insert(labels[i])
        }
        return out
    }
}

/// Shared helper: turn a refined PlanarMap face into `ShapeGeometry`, optionally
/// substituting a whole-shape primitive when the face is a single ring.
public enum ShapeGeometryBuilder {
    public static func build(
        face: PlanarMap.Face, tolerance: Double, straighten: Double, detectPrimitives: Bool,
        primitiveTolerance: Double? = nil
    ) -> ShapeGeometry? {
        if detectPrimitives, face.rings.count == 1, let poly = face.rings.first,
            let prim = PrimitiveDetect.detect(
                poly, tolerance: primitiveTolerance ?? (tolerance * 1.6), straighten: straighten)
        {
            return prim
        }
        if let refined = face.refined, !refined.isEmpty {
            return .refined(refined)
        }
        // Fallback: legacy polygonal rings.
        let rings = face.rings.filter { $0.count >= 3 }
        return rings.isEmpty ? nil : .rings(rings)
    }
}

extension ShapesMode {
    /// Part-aware palette membership: families ≥85% outside the subject are
    /// background families; in-subject pixels assigned to one reassign to the
    /// nearest family that has real in-subject support. Deterministic.
    static func partitionPalette(_ q: Quantized, walls: [Int]) -> Quantized {
        let count = q.palette.count
        guard count > 1, walls.count == q.indices.count else { return q }
        var inside = [Int](repeating: 0, count: count)
        var outside = [Int](repeating: 0, count: count)
        for i in 0..<q.indices.count {
            if walls[i] > 0 { inside[q.indices[i]] += 1 } else { outside[q.indices[i]] += 1 }
        }
        var isBackground = [Bool](repeating: false, count: count)
        var hasSubjectFamily = false
        for l in 0..<count {
            let total = inside[l] + outside[l]
            if total > 0 && Double(outside[l]) >= 0.85 * Double(total) {
                isBackground[l] = true
            } else if total > 0 {
                hasSubjectFamily = true
            }
        }
        guard hasSubjectFamily, isBackground.contains(true) else { return q }
        // Nearest in-subject family per background family (RGB distance).
        var remap = Array(0..<count)
        for l in 0..<count where isBackground[l] {
            var best = -1
            var bestd = Int.max
            for m in 0..<count where !isBackground[m] && inside[m] > 0 {
                let d = ColorQuantizer.dist2(q.palette[l], q.palette[m])
                if d < bestd || (d == bestd && m < best) {
                    bestd = d
                    best = m
                }
            }
            if best >= 0 { remap[l] = best }
        }
        var indices = q.indices
        for i in 0..<indices.count where walls[i] > 0 {
            indices[i] = remap[indices[i]]
        }
        return Quantized(
            width: q.width, height: q.height, palette: q.palette, indices: indices,
            paletteExactCount: q.paletteExactCount)
    }
}
