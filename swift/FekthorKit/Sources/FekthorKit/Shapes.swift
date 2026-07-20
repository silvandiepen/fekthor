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
    public init(colors: Int = 16, iters: Int = 8, epsilon: Double = 1.0, minArea: Double = 6.0) {
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
        var regs = ContourTracer.regions(q)
        // Paint back-to-front: larger regions first, smaller layered on top.
        regs.sort { a, b in
            if a.area != b.area { return a.area > b.area }
            return a.paletteIdx < b.paletteIdx
        }

        var doc = VectorDocument(width: img.width, height: img.height)
        var nextID = 0
        for r in regs {
            if r.area < config.minArea { continue }
            let outer = Geometry.simplifyClosed(r.outer, epsilon: config.epsilon)
            if outer.count < 3 { continue }
            var rings = [outer]
            for hole in r.holes {
                if Geometry.area(hole) < config.minArea { continue }
                let hs = Geometry.simplifyClosed(hole, epsilon: config.epsilon)
                if hs.count >= 3 { rings.append(hs) }
            }
            let color = q.palette[r.paletteIdx]
            doc.elements.append(.fill(FillShape(id: "fill-\(nextID)", color: color, rings: rings)))
            nextID += 1
        }
        return doc
    }
}
