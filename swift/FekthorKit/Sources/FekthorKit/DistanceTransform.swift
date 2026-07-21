import Foundation

/// Exact Euclidean distance transform (Felzenszwalb–Huttenlocher, two passes of
/// the 1D lower-envelope-of-parabolas algorithm, O(n)). Computed once per Strokes
/// conversion and shared by both per-stroke width estimation (2×dt at a centreline
/// point ≈ the local stroke width) and per-branch spur pruning (a thin branch has
/// a small dt, so it is not pruned by the width of thick outlines).
///
/// Deterministic: purely arithmetic, no hashing or ordering into the result.
public enum DistanceTransform {
    /// Exact squared Euclidean distance transform of a 1D sampled cost function.
    /// `f[i]` is 0 at a seed and a large value elsewhere. Returns, for each index,
    /// the minimum over j of `(i-j)² + f[j]`.
    static func edt1d(_ f: [Double]) -> [Double] {
        let n = f.count
        if n == 0 { return [] }
        var d = [Double](repeating: 0, count: n)
        var v = [Int](repeating: 0, count: n)  // parabola vertices
        var z = [Double](repeating: 0, count: n + 1)  // envelope break points
        var k = 0
        v[0] = 0
        z[0] = -.infinity
        z[1] = .infinity
        for q in 1..<n {
            var s = intersect(f, q, v[k])
            while s <= z[k] {
                k -= 1
                s = intersect(f, q, v[k])
            }
            k += 1
            v[k] = q
            z[k] = s
            z[k + 1] = .infinity
        }
        k = 0
        for q in 0..<n {
            while z[k + 1] < Double(q) { k += 1 }
            let dq = Double(q - v[k])
            d[q] = dq * dq + f[v[k]]
        }
        return d
    }

    /// x-coordinate where the parabolas rooted at `p` and `q` intersect.
    @inline(__always)
    private static func intersect(_ f: [Double], _ p: Int, _ q: Int) -> Double {
        ((f[p] + Double(p * p)) - (f[q] + Double(q * q))) / Double(2 * p - 2 * q)
    }

    /// Exact Euclidean distance (px) from every pixel to the nearest `seed` pixel.
    /// Seed pixels have distance 0. If there are no seeds, every distance is a
    /// large finite value (never used in practice: the foreground always has a
    /// background boundary and drawings always have junction-free branches).
    public static func distance(fromSeeds seeds: [Bool], width w: Int, height h: Int) -> [Double] {
        let n = w * h
        // Any squared distance is < w²+h²; use it as the "no seed reached" cost.
        let big = Double(w * w + h * h + 1)
        var f = [Double](repeating: 0, count: n)
        for i in 0..<n { f[i] = seeds[i] ? 0 : big }

        // Pass 1: transform along columns.
        var col = [Double](repeating: 0, count: h)
        for x in 0..<w {
            for y in 0..<h { col[y] = f[y * w + x] }
            let dcol = edt1d(col)
            for y in 0..<h { f[y * w + x] = dcol[y] }
        }
        // Pass 2: transform along rows; take the square root for px distance.
        var out = [Double](repeating: 0, count: n)
        var row = [Double](repeating: 0, count: w)
        for y in 0..<h {
            let r = y * w
            for x in 0..<w { row[x] = f[r + x] }
            let drow = edt1d(row)
            for x in 0..<w { out[r + x] = drow[x].squareRoot() }
        }
        return out
    }

    /// Distance (px) from every pixel to the nearest **background** (non-foreground)
    /// in-image pixel. For a foreground/centreline pixel this is ≈ half the local
    /// stroke width, so `2 × dt` recovers the width.
    public static func toBackground(_ mask: Mask) -> [Double] {
        let w = mask.width
        let h = mask.height
        var bg = [Bool](repeating: false, count: w * h)
        for i in 0..<(w * h) { bg[i] = !mask.fg[i] }
        return distance(fromSeeds: bg, width: w, height: h)
    }
}
