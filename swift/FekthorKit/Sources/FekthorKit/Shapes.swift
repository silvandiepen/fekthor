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
    public init(
        colors: Int = 16, iters: Int = 8, epsilon: Double = 2.0, simplicity: Double = 0.3,
        autoColors: Bool = true, smoothing: Double = 1.0, straighten: Double = 0.5,
        autoColorMinFraction: Double = 0.004
    ) {
        self.colors = colors
        self.iters = iters
        self.epsilon = epsilon
        self.simplicity = simplicity
        self.autoColors = autoColors
        self.smoothing = smoothing
        self.straighten = straighten
        self.autoColorMinFraction = autoColorMinFraction
    }
}

public enum ShapesMode {
    public struct Output {
        public var document: VectorDocument
        public var detail: [String: Double]
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
        let q =
            config.autoColors
            ? AlphaLabels.quantize(
                img, maxColors: max(2, config.colors),
                minFraction: config.autoColorMinFraction, alphaStats: alphaStats,
                exactPalette: config.autoColorMinFraction <= 0.002)
            : ColorQuantizer.quantize(img, k: config.colors, iters: config.iters)
        let transparentLabel = AlphaLabels.transparentLabel(
            paletteCount: q.palette.count, alphaStats: alphaStats)
        let quantized = AlphaLabels.withTransparentLabel(
            img, quantized: q, transparentLabel: transparentLabel)

        // Optionally merge similar / small regions for cleaner, simpler shapes.
        let labels: [Int]
        let colors: [RGB]
        if config.simplicity > 0 {
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
