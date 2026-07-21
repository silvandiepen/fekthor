import Foundation

/// Perceptual colour in the Oklab space (Björn Ottosson, 2020).
///
/// Oklab makes "shade of one hue" (a lightness change along `L`) perceptually
/// separable from "different hue" (a move in the `a`/`b` chroma plane). Flatten
/// (plan 07) exploits this: it *cheapens* lightness distance and *inflates*
/// chroma distance so touching shade families collapse while distinct hues stay
/// apart. Greys/blacks/whites have a ≈ b ≈ 0, so they are hue-less and separate
/// from colours by chroma alone — no neutral special-casing is needed.
public struct OklabColor: Equatable {
    public var L: Double
    public var a: Double
    public var b: Double

    public init(L: Double, a: Double, b: Double) {
        self.L = L
        self.a = a
        self.b = b
    }

    /// sRGB channel (0…255) → linear light (0…1). Standard sRGB EOTF.
    @inline(__always)
    static func linearise(_ channel: Double) -> Double {
        let c = channel / 255.0
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// sRGB (0…255 doubles) → Oklab, via the published Ottosson constants.
    @inline(__always)
    public static func from(r: Double, g: Double, b: Double) -> OklabColor {
        let R = linearise(r), G = linearise(g), B = linearise(b)
        let l = 0.4122214708 * R + 0.5363325363 * G + 0.0514459929 * B
        let m = 0.2119034982 * R + 0.6806995451 * G + 0.1073969566 * B
        let s = 0.0883024619 * R + 0.2817188376 * G + 0.6299787005 * B
        let l_ = Foundation.cbrt(l)
        let m_ = Foundation.cbrt(m)
        let s_ = Foundation.cbrt(s)
        return OklabColor(
            L: 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
            a: 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
            b: 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_)
    }

    @inline(__always)
    public static func from(_ c: RGB) -> OklabColor {
        from(r: Double(c.r), g: Double(c.g), b: Double(c.b))
    }

    /// The single flatten metric — the one implementation every call site uses.
    ///
    ///   d² = wL·ΔL² + wC·(Δa² + Δb²),  wL = 1 − 0.85·flatten,  wC = 1 + 2·flatten
    ///
    /// `flatten` ∈ 0…1. At 0 lightness and chroma weigh equally (a plain
    /// perceptual distance); as it rises, lightness differences become nearly
    /// free while chroma differences grow expensive, so shades of one hue merge
    /// and different hues stay apart. Never call site re-derives these weights.
    @inline(__always)
    public static func flattenDistance(_ x: OklabColor, _ y: OklabColor, flatten: Double)
        -> Double
    {
        let wL = 1.0 - 0.85 * flatten
        let wC = 1.0 + 2.0 * flatten
        let dL = x.L - y.L
        let da = x.a - y.a
        let db = x.b - y.b
        return wL * dL * dL + wC * (da * da + db * db)
    }
}
