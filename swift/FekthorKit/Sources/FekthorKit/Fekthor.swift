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
        /// Geometry-refinement straighten strength (0…1): scales the line-fit
        /// tolerance so near-straight runs collapse to single lines (plan 02).
        public var straighten: Double
        /// Auto-detect dominant colours (excludes anti-aliasing) vs fixed count.
        public var autoColors: Bool
        /// Minimum source fraction for an auto-detected flat colour.
        public var autoColorMinFraction: Double
        /// Flatten strength (0…1, Shapes only): collapse shade families (same hue,
        /// different lightness) into flat colours via the hue-weighted Oklab metric.
        /// 0 = byte-identical to the non-flatten pipeline (plan 07).
        public var flatten: Double
        /// ML part awareness (Vision instance masks) for Shapes. Opt-in;
        /// model output may vary across OS versions, so it is excluded from
        /// the deterministic eval floors.
        public var partAware: Bool
        /// Overrides the estimated stroke width in Strokes mode (adjustable).
        public var strokeWidth: Double?
        /// Uniform width: every stroke shares the median width (no manual override).
        public var uniformStrokeWidth: Bool
        /// Where Strokes lines come from (auto / centreline / region edges).
        public var strokeSource: StrokeSource
        /// Stroke end-cap style (round/butt/square).
        public var strokeCap: LineCap
        /// Opt-in taper: narrowing tails become outline fills (default off).
        public var taper: Bool
        /// Optional line-colour override for the coloring plate (region edges).
        public var lineColor: RGB?
        public init(
            colors: Int = 16, epsilon: Double = 1.0, minArea: Double = 6.0, threshold: UInt8 = 128,
            simplicity: Double = 0.3, smoothing: Double = 0.65, straighten: Double = 0.5,
            autoColors: Bool = true, autoColorMinFraction: Double = 0.004, flatten: Double = 0,
            partAware: Bool = false,
            strokeWidth: Double? = nil, uniformStrokeWidth: Bool = false,
            strokeSource: StrokeSource = .auto, strokeCap: LineCap = .round, taper: Bool = false,
            lineColor: RGB? = nil
        ) {
            self.colors = colors
            self.epsilon = epsilon
            self.minArea = minArea
            self.threshold = threshold
            self.simplicity = simplicity
            self.smoothing = smoothing
            self.straighten = straighten
            self.autoColors = autoColors
            self.autoColorMinFraction = autoColorMinFraction
            self.flatten = flatten
            self.partAware = partAware
            self.strokeWidth = strokeWidth
            self.uniformStrokeWidth = uniformStrokeWidth
            self.strokeSource = strokeSource
            self.strokeCap = strokeCap
            self.taper = taper
            self.lineColor = lineColor
        }
    }

    public struct Result {
        public var document: VectorDocument
        public var svg: String
        public var rendered: RasterImage
        public var metrics: Metrics
        /// Mode-aware quality score (see `Quality`). Comparable across modes.
        public var quality: QualityScore
        /// The concrete mode used for conversion. For non-Auto calls this equals `mode`.
        public var resolvedMode: Mode
        /// Conversion diagnostics that are not part of the quality formula.
        public var detail: [String: Double]
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
        if mode == .auto {
            let detection = AutoMode.detect(img, options: options)
            var result = try convertConcrete(img, mode: detection.resolved, options: options)
            result.detail["auto.confidence"] = detection.confidence
            for (key, value) in detection.features {
                result.detail["auto.\(key)"] = value
            }
            result.resolvedMode = detection.resolved
            return result
        }
        return try convertConcrete(img, mode: mode, options: options)
    }

    static func convertConcrete(_ img: RasterImage, mode: Mode, options: Options = Options()) throws
        -> Result
    {
        let doc: VectorDocument
        var conversionDetail: [String: Double] = [:]
        switch mode {
        case .auto:
            throw EngineError.unsupported("Auto must resolve before concrete conversion")
        case .shapes:
            let output = ShapesMode.runWithDetail(
                img,
                config: ShapesConfig(
                    colors: options.colors, iters: 8, epsilon: options.epsilon,
                    simplicity: options.simplicity, autoColors: options.autoColors,
                    smoothing: options.smoothing, straighten: options.straighten,
                    autoColorMinFraction: options.autoColorMinFraction,
                    flatten: options.flatten, partAware: options.partAware))
            doc = output.document
            conversionDetail = output.detail
        case .strokes:
            doc = StrokesMode.run(
                img,
                config: StrokesConfig(
                    threshold: options.threshold, epsilon: max(1.0, options.epsilon),
                    widthOverride: options.strokeWidth,
                    uniformWidth: options.uniformStrokeWidth, source: options.strokeSource,
                    colors: options.colors, smoothing: options.smoothing,
                    straighten: options.straighten, cap: options.strokeCap, taper: options.taper,
                    lineColor: options.lineColor))
        case .gradient:
            doc = GradientMode.run(
                img,
                config: GradientConfig(
                    // Gradient regions are blobby shaded areas; a coarser boundary
                    // tolerance floor keeps the paths clean without costing fidelity.
                    colors: 64, epsilon: max(1.5, options.epsilon),
                    minArea: options.minArea, stops: 8,
                    // Fine fixed oversegmentation (a smooth gradient has no flat
                    // colours to auto-detect); moment-based agglomeration, driven by
                    // the Blend slider, decides the final regions, not banding.
                    autoColors: false, simplicity: min(1.0, max(0.0, options.simplicity)),
                    smoothing: options.smoothing, straighten: options.straighten))
        }
        let svg = SVGExport.toSVG(doc, smoothing: options.smoothing)
        let rendered = Rasterizer.render(doc, smoothing: options.smoothing)
        let metrics = Comparer.compare(img, rendered, tolerance: 8)
        let quality = Quality.score(
            source: img, document: doc, rendered: rendered, mode: mode)
        return Result(
            document: doc, svg: svg, rendered: rendered, metrics: metrics, quality: quality,
            resolvedMode: mode, detail: conversionDetail)
    }
}
