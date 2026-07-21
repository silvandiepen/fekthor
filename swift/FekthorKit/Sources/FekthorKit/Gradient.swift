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
    public init(
        colors: Int = 20, iters: Int = 8, epsilon: Double = 1.0, minArea: Double = 12.0,
        stops: Int = 6, autoColors: Bool = true, simplicity: Double = 0.15,
        bandMerge: Double = 44
    ) {
        self.colors = colors
        self.iters = iters
        self.epsilon = epsilon
        self.minArea = minArea
        self.stops = stops
        self.autoColors = autoColors
        self.simplicity = simplicity
        self.bandMerge = bandMerge
    }
}

public enum GradientMode {
    public static func run(_ img: RasterImage, config: GradientConfig = GradientConfig())
        -> VectorDocument
    {
        let q =
            config.autoColors
            ? ColorQuantizer.quantizeAuto(img, maxColors: max(2, config.colors), minFraction: 0.003)
            : ColorQuantizer.quantize(img, k: config.colors, iters: config.iters)

        // Merge adjacent bands of the same object (light→mid→shadow tones) into
        // one region so each becomes a single path filled with a gradient that
        // spans its full shading — fewer paths, richer gradients. Then trace via
        // the shared-edge planar map (gap-free) and fit a gradient per face.
        let s = min(1.0, max(0.0, config.simplicity))
        let areaFraction = 0.0004 + 0.0012 * s
        let minArea = Int(Double(img.width * img.height) * areaFraction)
        // Higher simplicity → merge more distant bands → fewer, richer gradients.
        let bandMerge = 26.0 + 60.0 * s
        let (labels, colors) = ComponentMerge.merge(
            indices: q.indices, palette: q.palette, width: img.width, height: img.height,
            minArea: minArea, colorThreshold: bandMerge * bandMerge)
        let faces = PlanarMap.faces(
            labels: labels, width: img.width, height: img.height, epsilon: config.epsilon)

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
            let paint = GradientFit.fit(
                img: img, labels: labels, label: face.label,
                bbox: (minx, miny, maxx, maxy), fallback: fallback, stops: config.stops)
            doc.elements.append(.fill(FillShape(id: "fill-\(nextID)", paint: paint, rings: rings)))
            nextID += 1
        }
        return doc
    }
}
