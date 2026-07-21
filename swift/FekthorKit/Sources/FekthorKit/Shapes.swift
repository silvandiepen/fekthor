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
    public init(
        colors: Int = 16, iters: Int = 8, epsilon: Double = 2.0, simplicity: Double = 0.3,
        autoColors: Bool = true, smoothing: Double = 0.65, straighten: Double = 0.5,
        autoColorMinFraction: Double = 0.004, flatten: Double = 0
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
                indices: quantized.indices, palette: quantized.palette,
                width: img.width, height: img.height, minArea: minArea,
                colorThreshold: colorThreshold, flatten: config.flatten,
                distinctGuard: ShapesMode.flattenSeparation)
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
                indices: quantized.indices, palette: quantized.palette, width: img.width, height: img.height,
                minArea: minArea, colorThreshold: colorThreshold)
        } else {
            labels = quantized.indices
            colors = quantized.palette
        }
        let transparentOutputLabels = AlphaLabels.outputLabels(
            labels: labels, indices: quantized.indices, transparentLabel: transparentLabel)

        // Shared-edge planar map with geometry refinement: adjacent regions use
        // identical refined boundary chains (no gaps), corners stay sharp, and
        // near-straight runs / roundings become lines / arcs / cubics (plan 02).
        let refineOpt = RefineOptions(
            tolerance: config.epsilon * 1.8, cornerAngle: 32, straighten: config.straighten,
            smoothing: config.smoothing)
        let faces = PlanarMap.faces(
            labels: labels, width: img.width, height: img.height, epsilon: config.epsilon,
            refine: refineOpt)

        var doc = VectorDocument(width: img.width, height: img.height)
        var nextID = 0
        for face in faces {
            if transparentOutputLabels.contains(face.label) { continue }
            let color = face.label < colors.count ? colors[face.label] : (0, 0, 0)
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
