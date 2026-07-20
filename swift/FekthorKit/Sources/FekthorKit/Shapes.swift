import Foundation

/// Shapes (flat fill) conversion mode.
///
/// Colour-quantize the source, trace each colour region into filled contours,
/// simplify, and assemble a back-to-front filled document. No strokes (D-002).
public struct ShapesConfig {
    public var colors: Int
    public var iters: Int
    public var epsilon: Double
    public var minArea: Double
    public init(colors: Int = 16, iters: Int = 8, epsilon: Double = 2.0, minArea: Double = 6.0) {
        self.colors = colors
        self.iters = iters
        self.epsilon = epsilon
        self.minArea = minArea
    }
}

public enum ShapesMode {
    public static func run(_ img: RasterImage, config: ShapesConfig = ShapesConfig())
        -> VectorDocument
    {
        let q = ColorQuantizer.quantize(img, k: config.colors, iters: config.iters)
        // Shared-edge planar map: adjacent regions use identical boundary points
        // (no gaps), and each shared chain is simplified once (removes jitter).
        let faces = PlanarMap.faces(
            labels: q.indices, width: img.width, height: img.height, epsilon: config.epsilon)

        var doc = VectorDocument(width: img.width, height: img.height)
        var nextID = 0
        for face in faces {
            let rings = face.rings.filter { $0.count >= 3 }
            if rings.isEmpty { continue }
            let color = q.palette[face.label]
            doc.elements.append(.fill(FillShape(id: "fill-\(nextID)", color: color, rings: rings)))
            nextID += 1
        }
        return doc
    }
}
