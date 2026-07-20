import Foundation

/// Fit a linear gradient to a colour region's true source pixels.
///
/// The gradient axis is the direction of the region's luminance change (a
/// least-squares plane fit); colours are sampled as the mean source colour in
/// bins along that axis, giving a multi-stop gradient that follows the shading.
public enum GradientFit {
    /// Solve a 3×3 system by Cramer's rule; returns nil if near-singular.
    private static func solve3(
        _ m: [[Double]], _ rhs: [Double]
    ) -> (Double, Double, Double)? {
        func det3(_ a: [[Double]]) -> Double {
            a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1])
                - a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0])
                + a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0])
        }
        let d = det3(m)
        if abs(d) < 1e-6 { return nil }
        func withCol(_ i: Int) -> [[Double]] {
            var c = m
            for r in 0..<3 { c[r][i] = rhs[r] }
            return c
        }
        return (det3(withCol(0)) / d, det3(withCol(1)) / d, det3(withCol(2)) / d)
    }

    public static func fit(
        img: RasterImage, q: Quantized, region: Region, stops stopCount: Int = 6
    ) -> Paint {
        let w = img.width
        let h = img.height
        let palette = q.palette[region.paletteIdx]
        let solidFallback = Paint.solid([palette.r, palette.g, palette.b])

        var minx = Int.max, miny = Int.max, maxx = Int.min, maxy = Int.min
        for p in region.outer {
            minx = min(minx, Int(p.x))
            miny = min(miny, Int(p.y))
            maxx = max(maxx, Int(p.x))
            maxy = max(maxy, Int(p.y))
        }
        minx = max(0, minx); miny = max(0, miny)
        maxx = min(w - 1, maxx); maxy = min(h - 1, maxy)
        if maxx < minx || maxy < miny { return solidFallback }

        // Collect the region's source pixels (matched by palette index).
        var px: [Double] = []
        var py: [Double] = []
        var pr: [Double] = []
        var pg: [Double] = []
        var pb: [Double] = []
        var pl: [Double] = []
        let idx = region.paletteIdx
        var y = miny
        while y <= maxy {
            var x = minx
            let row = y * w
            while x <= maxx {
                if q.indices[row + x] == idx {
                    let p = img.pixel(x, y)
                    let r = Double(p.0), g = Double(p.1), b = Double(p.2)
                    px.append(Double(x))
                    py.append(Double(y))
                    pr.append(r)
                    pg.append(g)
                    pb.append(b)
                    pl.append(0.299 * r + 0.587 * g + 0.114 * b)
                }
                x += 1
            }
            y += 1
        }
        let n = px.count
        if n < 24 { return solidFallback }

        // Least-squares luminance plane l = a + b*x + c*y → axis (b, c).
        var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0, syy = 0.0
        var sl = 0.0, slx = 0.0, sly = 0.0
        for i in 0..<n {
            sx += px[i]; sy += py[i]
            sxx += px[i] * px[i]; sxy += px[i] * py[i]; syy += py[i] * py[i]
            sl += pl[i]; slx += pl[i] * px[i]; sly += pl[i] * py[i]
        }
        let nn = Double(n)
        guard
            let (_, b, c) = solve3(
                [[nn, sx, sy], [sx, sxx, sxy], [sy, sxy, syy]], [sl, slx, sly])
        else { return solidFallback }
        let mag = (b * b + c * c).squareRoot()
        if mag < 2e-4 { return solidFallback }  // effectively flat → solid
        let ux = b / mag
        let uy = c / mag

        // Project onto the axis; find endpoints and bin colours.
        var tmin = Double.greatestFiniteMagnitude
        var tmax = -Double.greatestFiniteMagnitude
        var p0 = Pt(0, 0)
        var p1 = Pt(0, 0)
        for i in 0..<n {
            let t = px[i] * ux + py[i] * uy
            if t < tmin { tmin = t; p0 = Pt(px[i], py[i]) }
            if t > tmax { tmax = t; p1 = Pt(px[i], py[i]) }
        }
        let span = tmax - tmin
        if span < 1.0 { return solidFallback }

        let k = max(2, stopCount)
        var sumR = [Double](repeating: 0, count: k)
        var sumG = [Double](repeating: 0, count: k)
        var sumB = [Double](repeating: 0, count: k)
        var cnt = [Int](repeating: 0, count: k)
        for i in 0..<n {
            let t = px[i] * ux + py[i] * uy
            var bin = Int((t - tmin) / span * Double(k))
            bin = min(max(bin, 0), k - 1)
            sumR[bin] += pr[i]; sumG[bin] += pg[i]; sumB[bin] += pb[i]
            cnt[bin] += 1
        }
        var stops: [GradientStop] = []
        for bin in 0..<k where cnt[bin] > 0 {
            let ct = Double(cnt[bin])
            let color: RGB = (
                UInt8(min(255, max(0, sumR[bin] / ct))),
                UInt8(min(255, max(0, sumG[bin] / ct))),
                UInt8(min(255, max(0, sumB[bin] / ct)))
            )
            let offset = (Double(bin) + 0.5) / Double(k)
            stops.append(GradientStop(color: color, offset: offset))
        }
        if stops.count < 2 { return solidFallback }
        // Anchor the outer stops at 0 and 1 for full coverage.
        stops[0].offset = 0.0
        stops[stops.count - 1].offset = 1.0
        return .linear(LinearGradient(p0: p0, p1: p1, stops: stops))
    }
}
