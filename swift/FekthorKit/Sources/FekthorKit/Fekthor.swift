import Foundation

/// Public entry point for the Fekthor engine.
public enum Fekthor {
    public struct Options {
        public var colors: Int
        public var epsilon: Double
        public var minArea: Double
        public var threshold: UInt8
        /// Region-merge strength for Shapes (0 = none, 1 = aggressive).
        public var simplicity: Double
        /// Curve smoothing strength (0 = polygonal, 1 = full).
        public var smoothing: Double
        /// Auto-detect dominant colours (excludes anti-aliasing) vs fixed count.
        public var autoColors: Bool
        /// Overrides the estimated stroke width in Strokes mode (adjustable).
        public var strokeWidth: Double?
        /// Where Strokes lines come from (auto / centreline / region edges).
        public var strokeSource: StrokeSource
        public init(
            colors: Int = 16, epsilon: Double = 1.0, minArea: Double = 6.0, threshold: UInt8 = 128,
            simplicity: Double = 0.3, smoothing: Double = 1.0, autoColors: Bool = true,
            strokeWidth: Double? = nil, strokeSource: StrokeSource = .auto
        ) {
            self.colors = colors
            self.epsilon = epsilon
            self.minArea = minArea
            self.threshold = threshold
            self.simplicity = simplicity
            self.smoothing = smoothing
            self.autoColors = autoColors
            self.strokeWidth = strokeWidth
            self.strokeSource = strokeSource
        }
    }

    public struct Result {
        public var document: VectorDocument
        public var svg: String
        public var rendered: RasterImage
        public var metrics: Metrics
        /// Mode-aware quality score (see `Quality`). Comparable across modes.
        public var quality: QualityScore
    }

    public enum EngineError: Error, CustomStringConvertible {
        case unsupported(String)
        public var description: String {
            switch self {
            case .unsupported(let m): return "unsupported: \(m)"
            }
        }
    }

    /// Convert a raster image to a vector document for the given mode, then
    /// render it back and score fidelity against the source.
    public static func convert(_ img: RasterImage, mode: Mode, options: Options = Options()) throws
        -> Result
    {
        let doc: VectorDocument
        switch mode {
        case .shapes:
            doc = ShapesMode.run(
                img,
                config: ShapesConfig(
                    colors: options.colors, iters: 8, epsilon: options.epsilon,
                    simplicity: options.simplicity, autoColors: options.autoColors))
        case .strokes:
            doc = StrokesMode.run(
                img,
                config: StrokesConfig(
                    threshold: options.threshold, epsilon: max(1.0, options.epsilon),
                    widthOverride: options.strokeWidth, source: options.strokeSource,
                    colors: options.colors))
        case .gradient:
            doc = GradientMode.run(
                img,
                config: GradientConfig(
                    colors: 32, epsilon: max(1.0, options.epsilon),
                    minArea: options.minArea,
                    // Fixed fine bands (a smooth gradient has no flat colours to
                    // auto-detect), merged into rich gradient regions by Simplicity.
                    autoColors: false, simplicity: max(0.25, options.simplicity)))
        }
        let svg = SVGExport.toSVG(doc, smoothing: options.smoothing)
        let rendered = Rasterizer.render(doc, smoothing: options.smoothing)
        let metrics = Comparer.compare(img, rendered, tolerance: 8)
        let quality = Quality.score(
            source: img, document: doc, rendered: rendered, mode: mode)
        return Result(
            document: doc, svg: svg, rendered: rendered, metrics: metrics, quality: quality)
    }
}
