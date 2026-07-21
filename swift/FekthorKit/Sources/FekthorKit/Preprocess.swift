import Foundation

/// Edge-preserving texture flattening for the gradient pipeline.
///
/// Shaded 3D sources carry directional micro-texture (hair strands, fabric
/// weave, render noise) that quantizes into hundreds of speckle blobs — noise
/// the vector output can neither keep nor afford. The classic Kuwahara filter
/// replaces each pixel with the mean of the least-variance quadrant around it:
/// texture — high variance in *every* quadrant — collapses to its local mean
/// (painterly flattening), while a pixel beside an object boundary always has
/// one quadrant entirely on its own side, so edges stay crisp instead of
/// blurring. O(n) via integral-image box sums; deterministic (fixed quadrant
/// tie-break order).
public enum Preprocess {
    /// Summed-area table with a zero guard row/column: `sums[(y+1)*(w+1)+x+1]`
    /// is the inclusive prefix sum of `src[0…y][0…x]`.
    static func integral(_ src: [Double], width w: Int, height h: Int) -> [Double] {
        var out = [Double](repeating: 0, count: (w + 1) * (h + 1))
        for y in 0..<h {
            var rowSum = 0.0
            let srcRow = y * w
            let outRow = (y + 1) * (w + 1)
            let prevRow = y * (w + 1)
            for x in 0..<w {
                rowSum += src[srcRow + x]
                out[outRow + x + 1] = out[prevRow + x + 1] + rowSum
            }
        }
        return out
    }

    @inline(__always)
    static func boxSum(
        _ sums: [Double], _ w: Int, _ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int
    ) -> Double {
        let rowA = y0 * (w + 1), rowB = (y1 + 1) * (w + 1)
        return sums[rowB + x1 + 1] - sums[rowB + x0] - sums[rowA + x1 + 1] + sums[rowA + x0]
    }

    /// Fraction of pixels whose luminance deviates from the local 3×3 mean by
    /// more than `threshold` — a scale-normalised micro-texture density
    /// (computed on a ≤512px thumbnail so the answer is resolution-independent).
    /// Smooth digital paintings measure ≈0.03, strand/fabric-textured renders
    /// ≈0.18.
    public static func textureFraction(_ img: RasterImage, threshold: Double = 10) -> Double {
        let thumb = img.scaled(maxDimension: 512)
        let w = thumb.width, h = thumb.height
        let n = w * h
        guard n > 0, w > 2, h > 2 else { return 0 }
        var lum = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let o = i * 4
            lum[i] =
                0.2126 * Double(thumb.data[o]) + 0.7152 * Double(thumb.data[o + 1])
                + 0.0722 * Double(thumb.data[o + 2])
        }
        let sums = integral(lum, width: w, height: h)
        var textured = 0
        for y in 0..<h {
            let y0 = max(0, y - 1), y1 = min(h - 1, y + 1)
            for x in 0..<w {
                let x0 = max(0, x - 1), x1 = min(w - 1, x + 1)
                let count = Double((x1 - x0 + 1) * (y1 - y0 + 1))
                let mean = boxSum(sums, w, x0, y0, x1, y1) / count
                if abs(lum[y * w + x] - mean) > threshold { textured += 1 }
            }
        }
        return Double(textured) / Double(n)
    }

    /// Plain box blur — the *unbiased* local mean (Kuwahara means carry a
    /// bright bias toward the flattest quadrant). Used as the paint-fitting
    /// reference: texture averages out, true colours stay put. Alpha passes
    /// through untouched.
    public static func boxSmooth(_ img: RasterImage, radius: Int) -> RasterImage {
        let w = img.width, h = img.height
        let n = w * h
        guard n > 0, radius > 0 else { return img }
        var out = img.data
        for ch in 0..<3 {
            var p = [Double](repeating: 0, count: n)
            for i in 0..<n { p[i] = Double(img.data[i * 4 + ch]) }
            let sums = integral(p, width: w, height: h)
            for y in 0..<h {
                let y0 = max(0, y - radius), y1 = min(h - 1, y + radius)
                for x in 0..<w {
                    let x0 = max(0, x - radius), x1 = min(w - 1, x + radius)
                    let count = Double((x1 - x0 + 1) * (y1 - y0 + 1))
                    let v = boxSum(sums, w, x0, y0, x1, y1) / count
                    out[(y * w + x) * 4 + ch] = UInt8(min(255, max(0, v.rounded())))
                }
            }
        }
        return RasterImage(width: w, height: h, data: out)
    }

    /// Kuwahara filter with square quadrants of side `radius+1`. Alpha passes
    /// through untouched.
    public static func kuwahara(_ img: RasterImage, radius: Int) -> RasterImage {
        let w = img.width, h = img.height
        let n = w * h
        guard n > 0, radius > 0, w > radius, h > radius else { return img }

        var r = [Double](repeating: 0, count: n)
        var g = [Double](repeating: 0, count: n)
        var b = [Double](repeating: 0, count: n)
        var lum = [Double](repeating: 0, count: n)
        var lum2 = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let o = i * 4
            r[i] = Double(img.data[o])
            g[i] = Double(img.data[o + 1])
            b[i] = Double(img.data[o + 2])
            let l = 0.2126 * r[i] + 0.7152 * g[i] + 0.0722 * b[i]
            lum[i] = l
            lum2[i] = l * l
        }
        let ir = integral(r, width: w, height: h)
        let ig = integral(g, width: w, height: h)
        let ib = integral(b, width: w, height: h)
        let il = integral(lum, width: w, height: h)
        let il2 = integral(lum2, width: w, height: h)

        var out = img.data
        for y in 0..<h {
            for x in 0..<w {
                // Quadrant corner offsets relative to (x, y), fixed order for
                // the deterministic strict-less tie-break below.
                var bestVar = Double.greatestFiniteMagnitude
                var bestR = 0.0, bestG = 0.0, bestB = 0.0
                for q in 0..<4 {
                    let x0 = q & 1 == 0 ? max(0, x - radius) : x
                    let x1 = q & 1 == 0 ? x : min(w - 1, x + radius)
                    let y0 = q & 2 == 0 ? max(0, y - radius) : y
                    let y1 = q & 2 == 0 ? y : min(h - 1, y + radius)
                    let count = Double((x1 - x0 + 1) * (y1 - y0 + 1))
                    let sl = boxSum(il, w, x0, y0, x1, y1)
                    let sl2 = boxSum(il2, w, x0, y0, x1, y1)
                    let variance = max(0, sl2 / count - (sl / count) * (sl / count))
                    if variance < bestVar {
                        bestVar = variance
                        bestR = boxSum(ir, w, x0, y0, x1, y1) / count
                        bestG = boxSum(ig, w, x0, y0, x1, y1) / count
                        bestB = boxSum(ib, w, x0, y0, x1, y1) / count
                    }
                }
                let o = (y * w + x) * 4
                out[o] = UInt8(min(255, max(0, bestR.rounded())))
                out[o + 1] = UInt8(min(255, max(0, bestG.rounded())))
                out[o + 2] = UInt8(min(255, max(0, bestB.rounded())))
            }
        }
        return RasterImage(width: w, height: h, data: out)
    }
}
