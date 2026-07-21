import Foundation

/// Gradient conversion mode.
///
/// Like Shapes, but each colour region is painted with a fitted linear gradient
/// following its shading instead of a flat colour — for shaded / 3D-style art.
public struct GradientConfig {
    public var colors: Int
    public var iters: Int
    public var epsilon: Double
    public var minArea: Double
    public var stops: Int
    public var autoColors: Bool
    /// Region-merge strength (merges shaded bands of one object).
    public var simplicity: Double
    /// Max colour distance for merging adjacent bands into one gradient region.
    public var bandMerge: Double
    /// Curve smoothing strength for the refined cubics (0 polygonal … 1 full).
    public var smoothing: Double
    /// Straighten strength (0…1): greedier line fitting for near-straight runs.
    public var straighten: Double
    public init(
        colors: Int = 20, iters: Int = 8, epsilon: Double = 1.0, minArea: Double = 12.0,
        stops: Int = 6, autoColors: Bool = true, simplicity: Double = 0.15,
        bandMerge: Double = 44, smoothing: Double = 1.0, straighten: Double = 0.5
    ) {
        self.colors = colors
        self.iters = iters
        self.epsilon = epsilon
        self.minArea = minArea
        self.stops = stops
        self.autoColors = autoColors
        self.simplicity = simplicity
        self.bandMerge = bandMerge
        self.smoothing = smoothing
        self.straighten = straighten
    }
}

public enum GradientMode {
    /// The moment-merged region segmentation for one image + config. Shared by
    /// `run` and the plan-05 tests (background-single-region, blend monotonicity)
    /// so those assertions exercise the real parameters, never a copy that drifts.
    static func segment(_ img: RasterImage, config: GradientConfig)
        -> (labels: [Int], colors: [RGB])
    {
        let q =
            config.autoColors
            ? ColorQuantizer.quantizeAuto(img, maxColors: max(2, config.colors), minFraction: 0.003)
            : ColorQuantizer.quantize(img, k: config.colors, iters: config.iters)
        // Merge adjacent bands of the same object (light→mid→shadow tones) into
        // one region so each becomes a single path filled with a gradient that
        // spans its full shading — fewer paths, richer gradients. Merging is driven
        // by real gradient-fit error (moment-based planar SSE), not raw colour
        // distance: a candidate pair merges only while the plane through the union
        // still explains it.
        let s = min(1.0, max(0.0, config.simplicity))
        // Blend τ: the per-(smaller-region)-pixel excess SSE tolerated when forcing
        // two regions onto one plane. Low Blend → tight (many regions); high →
        // coalescing. The mapping is calibrated so the default Blend keeps the
        // gradient eval rows above their floors while cutting shape count.
        let tau = 150.0 + 1200.0 * s
        let areaFraction = 0.00004 + 0.0002 * s
        let minArea = max(8, Int(Double(img.width * img.height) * areaFraction))
        return GradientRegions.segment(
            indices: q.indices, palette: q.palette, img: img, width: img.width, height: img.height,
            minArea: minArea, tau: tau)
    }

    public static func run(_ img: RasterImage, config: GradientConfig = GradientConfig())
        -> VectorDocument
    {
        // Trace the merged regions via the shared-edge planar map (gap-free) and
        // fit a gradient per face.
        let (labels, colors) = segment(img, config: config)
        let refineOpt = RefineOptions(
            tolerance: config.epsilon * 1.8, cornerAngle: 32, straighten: config.straighten,
            smoothing: config.smoothing)
        let faces = PlanarMap.faces(
            labels: labels, width: img.width, height: img.height, epsilon: config.epsilon,
            refine: refineOpt)

        var doc = VectorDocument(width: img.width, height: img.height)
        var nextID = 0
        for face in faces {
            let rings = face.rings.filter { $0.count >= 3 }
            if rings.isEmpty { continue }
            var minx = Int.max, miny = Int.max, maxx = Int.min, maxy = Int.min
            for ring in rings {
                for p in ring {
                    minx = min(minx, Int(p.x)); miny = min(miny, Int(p.y))
                    maxx = max(maxx, Int(p.x)); maxy = max(maxy, Int(p.y))
                }
            }
            let fallback = face.label < colors.count ? colors[face.label] : (0, 0, 0)
            let paint = GradientFit.fitRegion(
                img: img, labels: labels, label: face.label,
                bbox: (minx, miny, maxx, maxy), fallback: fallback, stops: config.stops)
            // Refined region boundaries; gradient regions are blobby, so no
            // whole-shape primitive substitution here.
            let geometry = ShapeGeometryBuilder.build(
                face: face, tolerance: config.epsilon, straighten: config.straighten,
                detectPrimitives: false) ?? .rings(rings)
            doc.elements.append(
                .fill(FillShape(id: "fill-\(nextID)", paint: paint, geometry: geometry)))
            nextID += 1
        }
        return doc
    }
}
