import Foundation

/// Render-back comparison metrics between a source raster and a rendered vector.
public struct Metrics: Codable, Sendable {
    /// Mean absolute per-channel difference over RGB (0 = identical).
    public var meanAbs: Double
    /// Fraction of pixels whose max RGB channel diff is within tolerance.
    public var exactPct: Double
    /// Peak signal-to-noise ratio in dB (higher is better).
    public var psnr: Double
    public var tolerance: Int
}

public enum Comparer {
    public static func compare(_ source: RasterImage, _ rendered: RasterImage, tolerance: Int = 8)
        -> Metrics
    {
        precondition(source.width == rendered.width && source.height == rendered.height)
        let n = source.width * source.height
        var sumAbs = 0
        var sumSq = 0
        var exact = 0
        source.data.withUnsafeBufferPointer { a in
            rendered.data.withUnsafeBufferPointer { b in
                for i in 0..<n {
                    let o = i * 4
                    var maxd = 0
                    for c in 0..<3 {
                        let d = abs(Int(a[o + c]) - Int(b[o + c]))
                        sumAbs += d
                        sumSq += d * d
                        if d > maxd { maxd = d }
                    }
                    if maxd <= tolerance { exact += 1 }
                }
            }
        }
        let count = Double(n * 3)
        let meanAbs = Double(sumAbs) / count
        let mse = Double(sumSq) / count
        let psnr = mse <= Double.ulpOfOne ? Double.infinity : 20 * log10(255.0) - 10 * log10(mse)
        return Metrics(
            meanAbs: meanAbs, exactPct: 100 * Double(exact) / Double(n), psnr: psnr,
            tolerance: tolerance)
    }
}
