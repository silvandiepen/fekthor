import Foundation

/// Public entry point for the Fekthor engine.
public enum Fekthor {
    public struct Options {
        public var colors: Int
        public var epsilon: Double
        public var minArea: Double
        public var threshold: UInt8
        public init(
            colors: Int = 16, epsilon: Double = 1.0, minArea: Double = 6.0, threshold: UInt8 = 128
        ) {
            self.colors = colors
            self.epsilon = epsilon
            self.minArea = minArea
            self.threshold = threshold
        }
    }

    public struct Result {
        public var document: VectorDocument
        public var svg: String
        public var rendered: RasterImage
        public var metrics: Metrics
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
                    minArea: options.minArea))
        case .strokes, .gradient:
            throw EngineError.unsupported("mode not implemented yet: \(mode.rawValue)")
        }
        let svg = SVGExport.toSVG(doc)
        let rendered = Rasterizer.render(doc)
        let metrics = Comparer.compare(img, rendered, tolerance: 8)
        return Result(document: doc, svg: svg, rendered: rendered, metrics: metrics)
    }
}
