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
    public init(
        colors: Int = 16, iters: Int = 8, epsilon: Double = 2.0, simplicity: Double = 0.3,
        autoColors: Bool = true, smoothing: Double = 1.0, straighten: Double = 0.5
    ) {
        self.colors = colors
        self.iters = iters
        self.epsilon = epsilon
        self.simplicity = simplicity
        self.autoColors = autoColors
        self.smoothing = smoothing
        self.straighten = straighten
    }
}

public enum ShapesMode {
    public static func run(_ img: RasterImage, config: ShapesConfig = ShapesConfig())
        -> VectorDocument
    {
        let q =
            config.autoColors
            ? ColorQuantizer.quantizeAuto(img, maxColors: max(2, config.colors), minFraction: 0.004)
            : ColorQuantizer.quantize(img, k: config.colors, iters: config.iters)

        // Optionally merge similar / small regions for cleaner, simpler shapes.
        let labels: [Int]
        let colors: [RGB]
        if config.simplicity > 0 {
            let s = min(1.0, max(0.0, config.simplicity))
            let minArea = Int(Double(img.width * img.height) * 0.0006 * s)
            let colorThreshold = 40.0 * 40.0 * s
            (labels, colors) = ComponentMerge.merge(
                indices: q.indices, palette: q.palette, width: img.width, height: img.height,
                minArea: minArea, colorThreshold: colorThreshold)
        } else {
            labels = q.indices
            colors = q.palette
        }

        // Shared-edge planar map with geometry refinement: adjacent regions use
        // identical refined boundary chains (no gaps), corners stay sharp, and
        // near-straight runs / roundings become lines / arcs / cubics (plan 02).
        let refineOpt = RefineOptions(
            tolerance: config.epsilon, cornerAngle: 32, straighten: config.straighten,
            smoothing: config.smoothing)
        let faces = PlanarMap.faces(
            labels: labels, width: img.width, height: img.height, epsilon: config.epsilon,
            refine: refineOpt)

        var doc = VectorDocument(width: img.width, height: img.height)
        var nextID = 0
        for face in faces {
            let color = face.label < colors.count ? colors[face.label] : (0, 0, 0)
            guard let geometry = ShapeGeometryBuilder.build(
                face: face, tolerance: config.epsilon, straighten: config.straighten,
                detectPrimitives: true)
            else { continue }
            doc.elements.append(
                .fill(FillShape(id: "fill-\(nextID)", color: color, geometry: geometry)))
            nextID += 1
        }
        return doc
    }
}

/// Shared helper: turn a refined PlanarMap face into `ShapeGeometry`, optionally
/// substituting a whole-shape primitive when the face is a single ring.
public enum ShapeGeometryBuilder {
    public static func build(
        face: PlanarMap.Face, tolerance: Double, straighten: Double, detectPrimitives: Bool
    ) -> ShapeGeometry? {
        if let refined = face.refined, !refined.isEmpty {
            if detectPrimitives, refined.count == 1, let poly = face.rings.first,
                let prim = PrimitiveDetect.detect(
                    poly, tolerance: tolerance, straighten: straighten)
            {
                return prim
            }
            return .refined(refined)
        }
        // Fallback: legacy polygonal rings.
        let rings = face.rings.filter { $0.count >= 3 }
        return rings.isEmpty ? nil : .rings(rings)
    }
}
