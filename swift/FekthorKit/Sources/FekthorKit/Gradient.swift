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
    public init(
        colors: Int = 20, iters: Int = 8, epsilon: Double = 1.0, minArea: Double = 12.0,
        stops: Int = 6
    ) {
        self.colors = colors
        self.iters = iters
        self.epsilon = epsilon
        self.minArea = minArea
        self.stops = stops
    }
}

public enum GradientMode {
    public static func run(_ img: RasterImage, config: GradientConfig = GradientConfig())
        -> VectorDocument
    {
        let q = ColorQuantizer.quantize(img, k: config.colors, iters: config.iters)
        var regs = ContourTracer.regions(q)
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
            let paint = GradientFit.fit(img: img, q: q, region: r, stops: config.stops)
            doc.elements.append(.fill(FillShape(id: "fill-\(nextID)", paint: paint, rings: rings)))
            nextID += 1
        }
        return doc
    }
}
