import Foundation

/// Settings search: find the slider combination that scores best on a
/// thumbnail, so "Auto-tune" can move Simplicity/Smoothing/Detail to values
/// matched to the image instead of one-size defaults. Deterministic: a fixed
/// grid, stable iteration order, strict-greater winner.
public enum AutoTune {
    public struct Outcome {
        public var options: Fekthor.Options
        public var resolvedMode: Mode
        public var score: Double
    }

    /// Thumbnail size for trial conversions. Big enough that Quality ranks
    /// settings the same way it does at working size; small enough that the
    /// whole grid stays interactive (~2-3 s).
    static let thumbnailMaxDimension = 384

    static let epsilonGrid = [1.0, 2.0, 3.2]
    static let simplicityGrid = [0.05, 0.2, 0.45, 0.7]
    static let smoothingGrid = [0.35, 0.65, 0.9]

    /// Search the grid around `base` (colour and mode settings are kept; only
    /// epsilon, simplicity and smoothing are tuned — the axes whose best value
    /// genuinely depends on the image). Returns the winning options.
    public static func search(_ img: RasterImage, mode: Mode, base: Fekthor.Options) -> Outcome {
        let thumb = img.scaled(maxDimension: thumbnailMaxDimension)
        let resolved = mode == .auto ? AutoMode.detect(thumb, options: base).resolved : mode

        var best = Outcome(options: base, resolvedMode: resolved, score: -1)
        for epsilon in epsilonGrid {
            for simplicity in simplicityGrid {
                for smoothing in smoothingGrid {
                    var options = base
                    options.epsilon = epsilon
                    options.simplicity = simplicity
                    options.smoothing = smoothing
                    guard let result = try? Fekthor.convert(thumb, mode: resolved, options: options)
                    else { continue }
                    let score = result.quality.overall
                    if score > best.score {
                        best = Outcome(options: options, resolvedMode: resolved, score: score)
                    }
                }
            }
        }
        return best
    }
}
