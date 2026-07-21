import Foundation

/// Whole-shape primitive detection (plan 02): recognise a closed ring that truly
/// is a circle, ellipse or (rounded) rectangle and represent it exactly, rather
/// than as a fitted path. Runs on the dense samples of a refined ring, in order
/// circle → ellipse → rect; the first that fits within tolerance wins.
///
/// Substitution is only offered for a single-ring shape (the caller enforces
/// this): a primitive replaces one outline, and any shared boundary the
/// neighbour keeps as a refined path stays within `tolerance` of it, so no
/// visible gap opens at working resolution.
public enum PrimitiveDetect {
    /// Try to recognise `ring` (dense, closed) as a primitive. Returns nil if none
    /// fits within tolerance — the caller then keeps the refined path.
    public static func detect(_ ring: [Pt], tolerance: Double, straighten: Double)
        -> ShapeGeometry?
    {
        let pts = PathRefine.dedupe(ring)
        guard pts.count >= 8 else { return nil }
        if let c = detectCircle(pts, tolerance: tolerance) { return c }
        if let e = detectEllipse(pts, tolerance: tolerance) { return e }
        if let r = detectRect(pts, tolerance: tolerance, straighten: straighten) { return r }
        return nil
    }

    // MARK: - Circle

    static func detectCircle(_ pts: [Pt], tolerance: Double) -> ShapeGeometry? {
        guard let fit = PathRefine.kasaCircle(pts) else { return nil }
        let c = Pt(fit.cx, fit.cy)
        let r = fit.r
        if r < 1 { return nil }
        let bb = bbox(pts)
        // Geometric sanity: a true circle has a roughly-square bbox, its centre
        // inside that bbox, and radius ≈ half the bbox. This rejects giant-radius
        // fits to gently-curved region boundaries (the far-off-canvas false
        // positives that otherwise pass the relative tolerance).
        let bw = bb.maxx - bb.minx
        let bh = bb.maxy - bb.miny
        if bw < 3 || bh < 3 { return nil }
        if max(bw, bh) / min(bw, bh) > 1.35 { return nil }
        if c.x < bb.minx - 2 || c.x > bb.maxx + 2 || c.y < bb.miny - 2 || c.y > bb.maxy + 2 {
            return nil
        }
        if r > 0.62 * max(bw, bh) || r < 0.35 * min(bw, bh) { return nil }
        let tol = max(tolerance, 0.015 * r)
        var maxDev = 0.0
        for p in pts { maxDev = max(maxDev, abs(PathRefine.dist(p, c) - r)) }
        return maxDev <= tol ? .circle(center: c, radius: r) : nil
    }

    static func bbox(_ pts: [Pt]) -> (minx: Double, miny: Double, maxx: Double, maxy: Double) {
        var minx = Double.infinity, miny = Double.infinity
        var maxx = -Double.infinity, maxy = -Double.infinity
        for p in pts {
            minx = min(minx, p.x)
            miny = min(miny, p.y)
            maxx = max(maxx, p.x)
            maxy = max(maxy, p.y)
        }
        return (minx, miny, maxx, maxy)
    }

    // MARK: - Ellipse (algebraic axis fit in the covariance frame)

    static func detectEllipse(_ pts: [Pt], tolerance: Double) -> ShapeGeometry? {
        let n = Double(pts.count)
        var cx = 0.0, cy = 0.0
        for p in pts {
            cx += p.x
            cy += p.y
        }
        cx /= n
        cy /= n
        // Orientation from the boundary covariance.
        var sxx = 0.0, syy = 0.0, sxy = 0.0
        for p in pts {
            let dx = p.x - cx
            let dy = p.y - cy
            sxx += dx * dx
            syy += dy * dy
            sxy += dx * dy
        }
        let rot = 0.5 * atan2(2 * sxy, sxx - syy)
        let ca = cos(rot)
        let sa = sin(rot)
        // Align points and solve for u=1/rx², v=1/ry² by least squares on x²u+y²v=1.
        var a11 = 0.0, a12 = 0.0, a22 = 0.0, b1 = 0.0, b2 = 0.0
        for p in pts {
            let dx = p.x - cx
            let dy = p.y - cy
            let x = dx * ca + dy * sa
            let y = -dx * sa + dy * ca
            let xx = x * x
            let yy = y * y
            a11 += xx * xx
            a12 += xx * yy
            a22 += yy * yy
            b1 += xx
            b2 += yy
        }
        let det = a11 * a22 - a12 * a12
        if abs(det) < 1e-9 { return nil }
        let u = (b1 * a22 - b2 * a12) / det
        let v = (a11 * b2 - a12 * b1) / det
        if u <= 0 || v <= 0 { return nil }
        let rx = 1 / u.squareRoot()
        let ry = 1 / v.squareRoot()
        if rx < 1 || ry < 1 { return nil }
        // Geometric sanity: centre inside the bbox and radii bounded by it, so a
        // gently-curved boundary can't pass as a giant ellipse.
        let bb = bbox(pts)
        if cx < bb.minx - 2 || cx > bb.maxx + 2 || cy < bb.miny - 2 || cy > bb.maxy + 2 {
            return nil
        }
        let diag = ((bb.maxx - bb.minx) * (bb.maxx - bb.minx)
            + (bb.maxy - bb.miny) * (bb.maxy - bb.miny)).squareRoot()
        if max(rx, ry) > 0.62 * diag { return nil }
        // A near-circular ellipse is better represented as a circle (handled
        // earlier); an extremely eccentric "ellipse" is usually a mis-fit.
        if max(rx, ry) / min(rx, ry) > 6 { return nil }
        let tol = max(tolerance, 0.015 * max(rx, ry))
        var maxDev = 0.0
        for p in pts {
            let dx = p.x - cx
            let dy = p.y - cy
            let x = dx * ca + dy * sa
            let y = -dx * sa + dy * ca
            let f = x * x * u + y * y * v
            let g = 2 * (x * x * u * u + y * y * v * v).squareRoot()
            let d = g < 1e-9 ? abs(f - 1) : abs(f - 1) / g
            maxDev = max(maxDev, d)
        }
        return maxDev <= tol ? .ellipse(center: Pt(cx, cy), rx: rx, ry: ry, rotation: rot) : nil
    }

    // MARK: - Rect / rounded rect

    static func detectRect(_ pts: [Pt], tolerance: Double, straighten: Double) -> ShapeGeometry? {
        let n = Double(pts.count)
        var cx = 0.0, cy = 0.0
        for p in pts {
            cx += p.x
            cy += p.y
        }
        cx /= n
        cy /= n
        var sxx = 0.0, syy = 0.0, sxy = 0.0
        for p in pts {
            let dx = p.x - cx
            let dy = p.y - cy
            sxx += dx * dx
            syy += dy * dy
            sxy += dx * dy
        }
        var rot = 0.5 * atan2(2 * sxy, sxx - syy)
        let ca = cos(rot)
        let sa = sin(rot)
        // Align and take the bounding box in the aligned frame.
        var minx = Double.infinity, maxx = -Double.infinity
        var miny = Double.infinity, maxy = -Double.infinity
        var aligned: [Pt] = []
        aligned.reserveCapacity(pts.count)
        for p in pts {
            let dx = p.x - cx
            let dy = p.y - cy
            let x = dx * ca + dy * sa
            let y = -dx * sa + dy * ca
            aligned.append(Pt(x, y))
            minx = min(minx, x)
            maxx = max(maxx, x)
            miny = min(miny, y)
            maxy = max(maxy, y)
        }
        let w = maxx - minx
        let h = maxy - miny
        if w < 2 || h < 2 { return nil }
        let bx = (minx + maxx) / 2
        let by = (miny + maxy) / 2
        // Boxiness gate: reject shapes that don't nearly fill their bounding box.
        let area = Geometry.area(pts)
        if area / (w * h) < 0.6 { return nil }

        let hw = w / 2
        let hh = h / 2
        let maxR = min(hw, hh)
        // Coarse search for the corner radius that best fits a rounded-rect SDF.
        var bestR = 0.0
        var bestDev = Double.infinity
        let steps = 24
        for s in 0...steps {
            let r = Double(s) / Double(steps) * maxR
            var dev = 0.0
            for a in aligned {
                dev = max(dev, abs(roundedBoxSDF(a.x - bx, a.y - by, hw, hh, r)))
                if dev >= bestDev { break }
            }
            if dev < bestDev {
                bestDev = dev
                bestR = r
            }
        }
        let tol = max(tolerance, 0.02 * max(w, h))
        if bestDev > tol { return nil }

        // Centre in the original frame.
        var centre = Pt(cx + bx * ca - by * sa, cy + bx * sa + by * ca)
        // Axis-snap: a near-axis-aligned rect exports as a plain (rounded) rect.
        if abs(rot) < (2 * .pi / 180) && straighten >= 0.5 {
            rot = 0
            // Re-fit the AABB in the original frame for an exact axis-aligned box.
            var nmnx = Double.infinity, nmxx = -Double.infinity
            var nmny = Double.infinity, nmxy = -Double.infinity
            for p in pts {
                nmnx = min(nmnx, p.x)
                nmxx = max(nmxx, p.x)
                nmny = min(nmny, p.y)
                nmxy = max(nmxy, p.y)
            }
            centre = Pt((nmnx + nmxx) / 2, (nmny + nmxy) / 2)
            return .rect(
                center: centre, w: nmxx - nmnx, h: nmxy - nmny, rotation: 0, cornerRadius: bestR)
        }
        return .rect(center: centre, w: w, h: h, rotation: rot, cornerRadius: bestR)
    }

    /// Signed distance from a point to a rounded box centred at the origin with
    /// half-extents (hw, hh) and corner radius r (negative inside).
    static func roundedBoxSDF(_ px: Double, _ py: Double, _ hw: Double, _ hh: Double, _ r: Double)
        -> Double
    {
        let qx = abs(px) - hw + r
        let qy = abs(py) - hh + r
        let ax = max(qx, 0)
        let ay = max(qy, 0)
        let outside = (ax * ax + ay * ay).squareRoot()
        let inside = min(max(qx, qy), 0)
        return outside + inside - r
    }
}
