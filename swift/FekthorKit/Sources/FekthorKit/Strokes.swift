import Foundation

/// Strokes (centreline) conversion mode.
///
/// Threshold to a foreground mask, thin to a 1px skeleton, trace the skeleton
/// into ordered graph edges, estimate a robust constant stroke width, and emit
/// adjustable stroke paths (D-008/D-014). Real strokes, never outlines.
/// Where stroke lines come from.
public enum StrokeSource: String, Sendable {
    /// Auto: centreline for line art, region edges for colour images.
    case auto
    /// Centreline of dark ink strokes (line art).
    case centreline
    /// Boundaries between colour regions (coloring-plate outlines).
    case edges
}

public struct StrokesConfig {
    public var threshold: UInt8
    public var epsilon: Double
    public var minLength: Int
    /// If set, overrides the estimated stroke width (the "adjustable" control).
    public var widthOverride: Double?
    public var source: StrokeSource
    public var colors: Int
    public init(
        threshold: UInt8 = 128, epsilon: Double = 1.5, minLength: Int = 2,
        widthOverride: Double? = nil, source: StrokeSource = .auto, colors: Int = 12
    ) {
        self.threshold = threshold
        self.epsilon = epsilon
        self.minLength = minLength
        self.widthOverride = widthOverride
        self.source = source
        self.colors = colors
    }
}

public enum StrokesMode {
    /// A greyscale, ≤2-colour image is treated as line art (use the centreline).
    static func isLineArt(_ img: RasterImage) -> Bool {
        let q = ColorQuantizer.quantizeAuto(img, maxColors: 6, minFraction: 0.02)
        guard q.palette.count <= 2 else { return false }
        return q.palette.allSatisfy { c in
            let mx = max(c.r, max(c.g, c.b))
            let mn = min(c.r, min(c.g, c.b))
            return Int(mx) - Int(mn) < 40
        }
    }

    public static func run(_ img: RasterImage, config: StrokesConfig = StrokesConfig())
        -> VectorDocument
    {
        let useEdges: Bool
        switch config.source {
        case .centreline: useEdges = false
        case .edges: useEdges = true
        case .auto: useEdges = !isLineArt(img)
        }
        return useEdges ? runEdges(img, config: config) : runCentreline(img, config: config)
    }

    /// Coloring-plate lines: trace the boundaries between colour regions.
    static func runEdges(_ img: RasterImage, config: StrokesConfig) -> VectorDocument {
        let q = ColorQuantizer.quantizeAuto(
            img, maxColors: max(2, config.colors), minFraction: 0.004)
        // Light merge to drop noise regions before tracing boundaries.
        let s = 0.2
        let minArea = Int(Double(img.width * img.height) * 0.0006 * s)
        let (labels, _) = ComponentMerge.merge(
            indices: q.indices, palette: q.palette, width: img.width, height: img.height,
            minArea: minArea, colorThreshold: 40.0 * 40.0 * s)
        let chains = PlanarMap.boundaryChains(
            labels: labels, width: img.width, height: img.height, epsilon: max(1.0, config.epsilon))
        let width = config.widthOverride ?? 2.0
        let minLen = max(3.0, width * 1.5)

        var doc = VectorDocument(width: img.width, height: img.height)
        var nextID = 0
        for chain in chains where chain.count >= 2 {
            let first = chain.first!
            let last = chain.last!
            let closed =
                chain.count > 3
                && (pow(first.x - last.x, 2) + pow(first.y - last.y, 2)) < 4.0
            if !closed && Double(chain.count) < minLen { continue }
            doc.elements.append(
                .stroke(
                    StrokePath(
                        id: "stroke-\(nextID)", color: (0, 0, 0), width: width, closed: closed,
                        points: chain)))
            nextID += 1
        }
        return doc
    }
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

    static func runCentreline(_ img: RasterImage, config: StrokesConfig) -> VectorDocument {
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
