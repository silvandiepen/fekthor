import Foundation

/// Fit the best gradient paint to a colour region's true source pixels.
///
/// Each final region is fit as a colour-aware **linear** gradient (axis = the
/// variance-weighted mean of the three per-channel plane gradients, so hue shifts
/// count, not just luminance) and as a **radial** gradient (best of three centre
/// candidates); the lower-RMSE of the two wins, with a **solid** fallback for
/// regions a gradient barely improves. Colours are bin means along the fit
/// parameter, giving a multi-stop ramp that follows the shading.
public enum GradientFit {
    /// Interpolate a stop list at a normalised parameter `t` (0…1). Stops are
    /// assumed sorted by offset with anchors near 0 and 1.
    @inline(__always)
    private static func evalStops(
        _ off: [Double], _ cr: [Double], _ cg: [Double], _ cb: [Double], _ t: Double
    ) -> (Double, Double, Double) {
        let k = off.count
        if k == 0 { return (0, 0, 0) }
        if t <= off[0] { return (cr[0], cg[0], cb[0]) }
        if t >= off[k - 1] { return (cr[k - 1], cg[k - 1], cb[k - 1]) }
        var i = 1
        while i < k && off[i] < t { i += 1 }
        let lo = i - 1
        let span = off[i] - off[lo]
        let f = span > 1e-9 ? (t - off[lo]) / span : 0
        return (
            cr[lo] + (cr[i] - cr[lo]) * f,
            cg[lo] + (cg[i] - cg[lo]) * f,
            cb[lo] + (cb[i] - cb[lo]) * f
        )
    }

    /// Build a multi-stop colour ramp along a per-pixel parameter `t∈[0,1]` (bin
    /// means) and return the ramp plus its residual sum of squares over the pixels.
    private static func rampAlong(
        _ t: [Double], _ pr: [Double], _ pg: [Double], _ pb: [Double], k: Int
    ) -> (off: [Double], cr: [Double], cg: [Double], cb: [Double], sse: Double)? {
        let n = t.count
        var sumR = [Double](repeating: 0, count: k)
        var sumG = [Double](repeating: 0, count: k)
        var sumB = [Double](repeating: 0, count: k)
        var cnt = [Int](repeating: 0, count: k)
        for i in 0..<n {
            var bin = Int(t[i] * Double(k))
            bin = min(max(bin, 0), k - 1)
            sumR[bin] += pr[i]; sumG[bin] += pg[i]; sumB[bin] += pb[i]
            cnt[bin] += 1
        }
        var off: [Double] = []
        var cr: [Double] = []
        var cg: [Double] = []
        var cb: [Double] = []
        for bin in 0..<k where cnt[bin] > 0 {
            let ct = Double(cnt[bin])
            off.append((Double(bin) + 0.5) / Double(k))
            cr.append(sumR[bin] / ct)
            cg.append(sumG[bin] / ct)
            cb.append(sumB[bin] / ct)
        }
        if off.count < 2 { return nil }
        off[0] = 0
        off[off.count - 1] = 1
        var sse = 0.0
        for i in 0..<n {
            let (r, g, b) = evalStops(off, cr, cg, cb, t[i])
            let dr = r - pr[i], dg = g - pg[i], db = b - pb[i]
            sse += dr * dr + dg * dg + db * db
        }
        return (off, cr, cg, cb, sse)
    }

    private static func makeStops(
        _ off: [Double], _ cr: [Double], _ cg: [Double], _ cb: [Double]
    ) -> [GradientStop] {
        var stops: [GradientStop] = []
        for i in 0..<off.count {
            let c: RGB = (
                UInt8(min(255, max(0, cr[i].rounded()))),
                UInt8(min(255, max(0, cg[i].rounded()))),
                UInt8(min(255, max(0, cb[i].rounded())))
            )
            stops.append(GradientStop(color: c, offset: off[i]))
        }
        return stops
    }

    /// Fit the best paint for a final gradient region: colour-aware **linear** vs
    /// **radial**, with a **solid** fallback for flat regions. Picks the lower-RMSE
    /// gradient; keeps solid when the best gradient barely beats the mean colour
    /// (plan 05 §2). Pixels are scanned once here — this runs per *final* region,
    /// never inside the merge loop.
    public static func fitRegion(
        img: RasterImage, labels: [Int], label idx: Int, bbox: (Int, Int, Int, Int),
        fallback: RGB, stops stopCount: Int = 6
    ) -> Paint {
        let w = img.width
        let h = img.height
        let solidFallback = Paint.solid([fallback.r, fallback.g, fallback.b])

        let minx = max(0, bbox.0), miny = max(0, bbox.1)
        let maxx = min(w - 1, bbox.2), maxy = min(h - 1, bbox.3)
        if maxx < minx || maxy < miny { return solidFallback }

        var px: [Double] = [], py: [Double] = []
        var pr: [Double] = [], pg: [Double] = [], pb: [Double] = [], pl: [Double] = []
        for y in miny...maxy {
            let row = y * w
            for x in minx...maxx where labels[row + x] == idx {
                let p = img.pixel(x, y)
                let r = Double(p.0), g = Double(p.1), b = Double(p.2)
                px.append(Double(x)); py.append(Double(y))
                pr.append(r); pg.append(g); pb.append(b)
                pl.append(0.299 * r + 0.587 * g + 0.114 * b)
            }
        }
        let n = px.count
        if n < 24 { return solidFallback }
        let k = max(2, stopCount)
        let nn = Double(n)

        // Solid reference RMSE (mean colour).
        var mr = 0.0, mg = 0.0, mb = 0.0
        for i in 0..<n { mr += pr[i]; mg += pg[i]; mb += pb[i] }
        mr /= nn; mg /= nn; mb /= nn
        var solidSSE = 0.0
        for i in 0..<n {
            let dr = pr[i] - mr, dg = pg[i] - mg, db = pb[i] - mb
            solidSSE += dr * dr + dg * dg + db * db
        }
        let solidRMSE = (solidSSE / (nn * 3)).squareRoot()

        // ---- Linear candidate: colour-aware axis ----
        // Per-channel least-squares plane l_C = a·x + b·y + c → gradient (a,b);
        // axis = variance-weighted mean of the three channel gradients (hue shifts
        // count, not just luminance).
        var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0, syy = 0.0
        for i in 0..<n {
            sx += px[i]; sy += py[i]
            sxx += px[i] * px[i]; sxy += px[i] * py[i]; syy += py[i] * py[i]
        }
        let sxxC = sxx - sx * sx / nn
        let sxyC = sxy - sx * sy / nn
        let syyC = syy - sy * sy / nn
        let det = sxxC * syyC - sxyC * sxyC
        func channelGrad(_ pc: [Double]) -> (Double, Double, Double) {
            var sc = 0.0, scx = 0.0, scy = 0.0, scc = 0.0
            for i in 0..<n {
                sc += pc[i]; scx += pc[i] * px[i]; scy += pc[i] * py[i]; scc += pc[i] * pc[i]
            }
            let varC = max(0, scc - sc * sc / nn) / nn
            if abs(det) < 1e-6 { return (0, 0, varC) }
            let scxC = scx - sc * sx / nn
            let scyC = scy - sc * sy / nn
            let a = (scxC * syyC - scyC * sxyC) / det
            let b = (sxxC * scyC - sxyC * scxC) / det
            return (a, b, varC)
        }
        let (arG, brG, vR) = channelGrad(pr)
        let (agG, bgG, vG) = channelGrad(pg)
        let (abG, bbG, vB) = channelGrad(pb)
        var axisX = vR * arG + vG * agG + vB * abG
        var axisY = vR * brG + vG * bgG + vB * bbG
        let amag = (axisX * axisX + axisY * axisY).squareRoot()

        var linear: (Paint, Double)? = nil
        if amag > 1e-9 {
            axisX /= amag; axisY /= amag
            var tmin = Double.greatestFiniteMagnitude
            var tmax = -Double.greatestFiniteMagnitude
            var p0 = Pt(0, 0), p1 = Pt(0, 0)
            for i in 0..<n {
                let t = px[i] * axisX + py[i] * axisY
                if t < tmin { tmin = t; p0 = Pt(px[i], py[i]) }
                if t > tmax { tmax = t; p1 = Pt(px[i], py[i]) }
            }
            let span = tmax - tmin
            if span >= 1.0 {
                var t = [Double](repeating: 0, count: n)
                for i in 0..<n {
                    t[i] = min(1, max(0, (px[i] * axisX + py[i] * axisY - tmin) / span))
                }
                if let ramp = rampAlong(t, pr, pg, pb, k: k) {
                    let rmse = (ramp.sse / (nn * 3)).squareRoot()
                    let paint = Paint.linear(
                        LinearGradient(
                            p0: p0, p1: p1,
                            stops: makeStops(ramp.off, ramp.cr, ramp.cg, ramp.cb)))
                    linear = (paint, rmse)
                }
            }
        }

        // ---- Radial candidate: 3 centre candidates, keep the lowest RMSE ----
        // Candidate centres: region centroid, and the centroids of the brightest
        // and darkest 10% of pixels (a highlight/shadow focus).
        let cxAll = sx / nn, cyAll = sy / nn
        let order = (0..<n).sorted { pl[$0] < pl[$1] }
        let tenth = max(1, n / 10)
        func centroid(_ idxs: ArraySlice<Int>) -> (Double, Double) {
            var ax = 0.0, ay = 0.0
            for i in idxs { ax += px[i]; ay += py[i] }
            let c = Double(idxs.count)
            return (ax / c, ay / c)
        }
        let dark = centroid(order[0..<tenth])
        let bright = centroid(order[(n - tenth)..<n])
        let candidates = [(cxAll, cyAll), bright, dark]

        var radial: (Paint, Double)? = nil
        var dbuf = [Double](repeating: 0, count: n)
        for (ccx, ccy) in candidates {
            for i in 0..<n {
                let dx = px[i] - ccx, dy = py[i] - ccy
                dbuf[i] = (dx * dx + dy * dy).squareRoot()
            }
            let sorted = dbuf.sorted()
            let radius = sorted[min(n - 1, Int(0.95 * Double(n)))]
            if radius < 1.0 { continue }
            var t = [Double](repeating: 0, count: n)
            for i in 0..<n { t[i] = min(1, dbuf[i] / radius) }
            guard let ramp = rampAlong(t, pr, pg, pb, k: k) else { continue }
            let rmse = (ramp.sse / (nn * 3)).squareRoot()
            if radial == nil || rmse < radial!.1 {
                let paint = Paint.radial(
                    RadialGradient(
                        center: Pt(ccx, ccy), radius: radius,
                        stops: makeStops(ramp.off, ramp.cr, ramp.cg, ramp.cb)))
                radial = (paint, rmse)
            }
        }

        // ---- Choose ----
        var best: (Paint, Double)? = nil
        if let l = linear { best = l }
        if let r = radial, best == nil || r.1 < best!.1 { best = r }
        guard let (paint, rmse) = best else { return solidFallback }
        // Flat regions stay flat: only keep a gradient that clearly beats solid.
        if rmse * 0.985 >= solidRMSE { return solidFallback }
        return paint
    }
}
