import Foundation

/// Strokes (centreline) conversion mode.
///
/// Threshold to a foreground mask, thin to a 1px skeleton, trace the skeleton
/// into ordered graph edges, estimate a robust constant stroke width, and emit
/// adjustable stroke paths (D-008/D-014). Real strokes, never outlines.
public struct StrokesConfig {
    public var threshold: UInt8
    public var epsilon: Double
    public var minLength: Int
    /// If set, overrides the estimated stroke width (the "adjustable" control).
    public var widthOverride: Double?
    public init(
        threshold: UInt8 = 128, epsilon: Double = 1.5, minLength: Int = 2,
        widthOverride: Double? = nil
    ) {
        self.threshold = threshold
        self.epsilon = epsilon
        self.minLength = minLength
        self.widthOverride = widthOverride
    }
}

public enum StrokesMode {
    /// Sample a representative ink colour from the source under a skeleton point.
    static func sampleColor(_ img: RasterImage, _ p: Pt) -> RGB {
        let x = min(max(Int(p.x), 0), img.width - 1)
        let y = min(max(Int(p.y), 0), img.height - 1)
        let px = img.pixel(x, y)
        return (px.0, px.1, px.2)
    }

    public static func run(_ img: RasterImage, config: StrokesConfig = StrokesConfig())
        -> VectorDocument
    {
        let mask = Foreground.dark(img, threshold: config.threshold)
        let fgCount = mask.count
        let skel = Skeleton.thin(mask)
        let skelCount = max(1, skel.count)
        // Area / skeleton-length approximates the mean constant stroke width.
        let width = config.widthOverride ?? max(1.0, Double(fgCount) / Double(skelCount))
        let edges = SkeletonGraph.edges(skel)

        var doc = VectorDocument(width: img.width, height: img.height)
        var nextID = 0
        for edge in edges where edge.count >= config.minLength {
            let first = edge.first!
            let last = edge.last!
            let closed =
                edge.count > 3
                && (pow(first.x - last.x, 2) + pow(first.y - last.y, 2)) < 4.0
            let simplified =
                closed
                ? Geometry.simplifyClosed(edge, epsilon: config.epsilon)
                : Geometry.simplifyOpen(edge, epsilon: config.epsilon)
            if simplified.count < 2 { continue }
            let color = sampleColor(img, edge[edge.count / 2])
            doc.elements.append(
                .stroke(
                    StrokePath(
                        id: "stroke-\(nextID)", color: color, width: width, closed: closed,
                        points: simplified)))
            nextID += 1
        }
        return doc
    }
}
