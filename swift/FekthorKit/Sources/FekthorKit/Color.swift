import Foundation

public typealias RGB = (r: UInt8, g: UInt8, b: UInt8)

public struct Quantized {
    public let width: Int
    public let height: Int
    public let palette: [RGB]
    /// One palette index per pixel, row-major.
    public let indices: [Int]
}

public enum ColorQuantizer {
    @inline(__always)
    static func dist2(_ a: RGB, _ b: RGB) -> Int {
        let dr = Int(a.r) - Int(b.r)
        let dg = Int(a.g) - Int(b.g)
        let db = Int(a.b) - Int(b.b)
        return dr * dr + dg * dg + db * db
    }

    /// True if `c` lies on the blend line between two palette colours — i.e. it
    /// is an anti-aliasing colour, not a distinct feature colour.
    static func isBlend(_ c: RGB, _ palette: [RGB]) -> Bool {
        let cx = Double(c.r), cy = Double(c.g), cz = Double(c.b)
        for i in 0..<palette.count {
            for j in (i + 1)..<palette.count {
                let a = palette[i], b = palette[j]
                let ax = Double(a.r), ay = Double(a.g), az = Double(a.b)
                let abx = Double(b.r) - ax, aby = Double(b.g) - ay, abz = Double(b.b) - az
                let denom = abx * abx + aby * aby + abz * abz
                if denom < 1 { continue }
                let t = ((cx - ax) * abx + (cy - ay) * aby + (cz - az) * abz) / denom
                if t <= 0.12 || t >= 0.88 { continue }  // near an endpoint, not a blend
                let px = ax + t * abx, py = ay + t * aby, pz = az + t * abz
                let d2 = (cx - px) * (cx - px) + (cy - py) * (cy - py) + (cz - pz) * (cz - pz)
                if d2 < 22 * 22 { return true }
            }
        }
        return false
    }

    /// Assign every pixel to the nearest palette colour.
    static func assign(_ img: RasterImage, palette: [RGB]) -> Quantized {
        let n = img.width * img.height
        var indices = [Int](repeating: 0, count: n)
        for i in 0..<n {
            let o = i * 4
            let c: RGB = (img.data[o], img.data[o + 1], img.data[o + 2])
            var best = 0
            var bestd = Int.max
            for (j, p) in palette.enumerated() {
                let d = dist2(c, p)
                if d < bestd {
                    bestd = d
                    best = j
                }
            }
            indices[i] = best
        }
        return Quantized(width: img.width, height: img.height, palette: palette, indices: indices)
    }

    /// Detect the image's dominant flat colours, excluding anti-aliasing.
    ///
    /// Anti-aliasing colours sit in thin edge bands (low frequency) between two
    /// real colours, so a frequency-ranked, spread-filtered pick keeps the real
    /// flat colours and drops the blends. Every pixel then snaps to the nearest.
    public static func quantizeAuto(
        _ img: RasterImage, maxColors: Int, minFraction: Double
    ) -> Quantized {
        let n = img.width * img.height
        var hist: [Int: (count: Int, sum: (Int, Int, Int))] = [:]
        for i in 0..<n {
            let o = i * 4
            let r = Int(img.data[o]), g = Int(img.data[o + 1]), b = Int(img.data[o + 2])
            let key = (r >> 3) << 10 | (g >> 3) << 5 | (b >> 3)
            var e = hist[key] ?? (0, (0, 0, 0))
            e.count += 1
            e.sum.0 += r
            e.sum.1 += g
            e.sum.2 += b
            hist[key] = e
        }
        var buckets: [(count: Int, color: RGB)] = hist.values.map { v in
            (
                v.count,
                (
                    UInt8(v.sum.0 / v.count), UInt8(v.sum.1 / v.count),
                    UInt8(v.sum.2 / v.count)
                )
            )
        }
        buckets.sort {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.color < $1.color
        }
        let minCount = Int(Double(n) * minFraction)
        let minSep2 = 28 * 28
        var palette: [RGB] = []
        // Pass 1: the frequent flat colours.
        for b in buckets {
            if palette.count >= maxColors { break }
            if b.count < minCount { break }
            if palette.allSatisfy({ dist2($0, b.color) >= minSep2 }) {
                palette.append(b.color)
            }
        }
        if palette.isEmpty { palette.append(buckets.first?.color ?? (0, 0, 0)) }
        // Pass 2: keep smaller *distinct* feature colours (e.g. tiny black eyes)
        // but drop true anti-aliasing — colours that lie on the blend line
        // between two palette colours.
        let noiseFloor = max(6, minCount / 12)
        for b in buckets {
            if palette.count >= maxColors { break }
            if b.count >= minCount || b.count < noiseFloor { continue }
            if !palette.allSatisfy({ dist2($0, b.color) >= minSep2 }) { continue }
            if isBlend(b.color, palette) { continue }
            palette.append(b.color)
        }
        return assign(img, palette: palette)
    }

    /// Deterministic coarse-histogram seeded k-means (Lloyd) over RGB.
    public static func quantize(_ img: RasterImage, k: Int, iters: Int) -> Quantized {
        let n = img.width * img.height
        @inline(__always) func px(_ i: Int) -> RGB {
            let o = i * 4
            return (img.data[o], img.data[o + 1], img.data[o + 2])
        }

        // Coarse 4-bit-per-channel histogram for deterministic seeding.
        var hist: [Int: (count: Int, sum: (Int, Int, Int))] = [:]
        for i in 0..<n {
            let c = px(i)
            let kr = (Int(c.r) >> 4) << 8
            let kg = (Int(c.g) >> 4) << 4
            let kb = Int(c.b) >> 4
            let key = kr | kg | kb
            var e = hist[key] ?? (0, (0, 0, 0))
            e.count += 1
            e.sum.0 += Int(c.r)
            e.sum.1 += Int(c.g)
            e.sum.2 += Int(c.b)
            hist[key] = e
        }
        var buckets: [(count: Int, color: RGB)] = hist.values.map { v in
            (
                v.count,
                (
                    UInt8(v.sum.0 / v.count), UInt8(v.sum.1 / v.count),
                    UInt8(v.sum.2 / v.count)
                )
            )
        }
        buckets.sort {
            if $0.count != $1.count { return $0.count > $1.count }
            if $0.color.r != $1.color.r { return $0.color.r < $1.color.r }
            if $0.color.g != $1.color.g { return $0.color.g < $1.color.g }
            return $0.color.b < $1.color.b
        }

        // Greedy spread seeding: frequent buckets far from existing seeds.
        let minSep2 = 24 * 24
        var seeds: [RGB] = []
        for b in buckets {
            if seeds.count >= k { break }
            if seeds.allSatisfy({ dist2($0, b.color) >= minSep2 }) { seeds.append(b.color) }
        }
        for b in buckets {
            if seeds.count >= k { break }
            if !seeds.contains(where: { $0 == b.color }) { seeds.append(b.color) }
        }
        if seeds.isEmpty { seeds.append((0, 0, 0)) }

        // Lloyd iterations over a strided sample, then a final full pass.
        let stride = max(1, n / 200_000)
        var centroids = seeds
        for _ in 0..<iters {
            var sums = [(Int, Int, Int)](repeating: (0, 0, 0), count: centroids.count)
            var counts = [Int](repeating: 0, count: centroids.count)
            var i = 0
            while i < n {
                let c = px(i)
                var best = 0
                var bestd = Int.max
                for j in 0..<centroids.count {
                    let d = dist2(c, centroids[j])
                    if d < bestd {
                        bestd = d
                        best = j
                    }
                }
                sums[best].0 += Int(c.r)
                sums[best].1 += Int(c.g)
                sums[best].2 += Int(c.b)
                counts[best] += 1
                i += stride
            }
            for j in 0..<centroids.count where counts[j] > 0 {
                centroids[j] = (
                    UInt8(sums[j].0 / counts[j]),
                    UInt8(sums[j].1 / counts[j]),
                    UInt8(sums[j].2 / counts[j])
                )
            }
        }

        var indices = [Int](repeating: 0, count: n)
        for i in 0..<n {
            let c = px(i)
            var best = 0
            var bestd = Int.max
            for j in 0..<centroids.count {
                let d = dist2(c, centroids[j])
                if d < bestd {
                    bestd = d
                    best = j
                }
            }
            indices[i] = best
        }

        return Quantized(
            width: img.width, height: img.height, palette: centroids, indices: indices)
    }
}
