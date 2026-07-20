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
    public init(
        colors: Int = 16, iters: Int = 8, epsilon: Double = 2.0, simplicity: Double = 0.3,
        autoColors: Bool = true
    ) {
        self.colors = colors
        self.iters = iters
        self.epsilon = epsilon
        self.simplicity = simplicity
        self.autoColors = autoColors
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

        // Shared-edge planar map: adjacent regions use identical boundary points
        // (no gaps), and each shared chain is simplified once (removes jitter).
        let faces = PlanarMap.faces(
            labels: labels, width: img.width, height: img.height, epsilon: config.epsilon)

        var doc = VectorDocument(width: img.width, height: img.height)
        var nextID = 0
        for face in faces {
            let rings = face.rings.filter { $0.count >= 3 }
            if rings.isEmpty { continue }
            let color = face.label < colors.count ? colors[face.label] : (0, 0, 0)
            doc.elements.append(.fill(FillShape(id: "fill-\(nextID)", color: color, rings: rings)))
            nextID += 1
        }
        return doc
    }
}
