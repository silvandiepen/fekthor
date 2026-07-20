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
    /// Near-grey dark ink is snapped to pure black so B&W line art gets clean
    /// black lines instead of muddy near-blacks.
    static func sampleColor(_ img: RasterImage, _ p: Pt) -> RGB {
        let x = min(max(Int(p.x), 0), img.width - 1)
        let y = min(max(Int(p.y), 0), img.height - 1)
        let px = img.pixel(x, y)
        let r = Int(px.0), g = Int(px.1), b = Int(px.2)
        let spread = max(r, max(g, b)) - min(r, min(g, b))
        if spread < 28 && max(r, max(g, b)) < 128 {
            return (0, 0, 0)
        }
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
        // Trace skeleton edges, then merge them through junctions so a line
        // passing straight through a crossing stays one continuous stroke.
        let rawEdges = SkeletonGraph.edges(skel)
        let edges = SkeletonGraph.mergeByTangent(rawEdges)

        // A short leftover chain after merging is a spur/noise branch.
        let spurLen = max(6.0, width * 2.0)

        var doc = VectorDocument(width: img.width, height: img.height)
        var nextID = 0
        for edge in edges {
            let first = edge.first!
            let last = edge.last!
            let closed =
                edge.count > 3
                && (pow(first.x - last.x, 2) + pow(first.y - last.y, 2)) < 4.0
            if !closed && Double(edge.count) < spurLen { continue }
            if edge.count < 2 { continue }
            // Smooth the raw centreline, then simplify, then render as a curve.
            let smoothed =
                closed ? edge : Geometry.smoothPolyline(edge, window: 2, iterations: 2)
            let simplified =
                closed
                ? Geometry.simplifyClosed(smoothed, epsilon: config.epsilon)
                : Geometry.simplifyOpen(smoothed, epsilon: config.epsilon)
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
