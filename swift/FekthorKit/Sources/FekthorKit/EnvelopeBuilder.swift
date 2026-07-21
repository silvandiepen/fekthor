import Foundation

/// Opt-in variable-width stroke envelopes (Illustrator-style width profiles).
///
/// A hand-drawn line whose ink genuinely swells and thins is not faithful as a
/// constant-width stroke. When the dt-width profile varies enough, the whole
/// centreline is emitted as ONE closed outline fill: the centreline offset by
/// ±half-width down one side and back the other — exactly what Illustrator's
/// "Expand Appearance" produces for a width-profile stroke. Constant-width
/// strokes stay real strokes (editability first); closed loops are left alone
/// (a variable-width ring needs two rings and is rare in practice).
public enum EnvelopeBuilder {
    /// Minimum spread of the width profile before an envelope is worth the
    /// loss of stroke semantics: wide-to-narrow ratio and absolute pixels.
    static let minRatio = 1.45
    static let minSpreadPx = 1.5

    /// Returns a smooth closed envelope fill, or nil when the width profile is
    /// effectively constant (keep the stroke).
    public static func build(
        chain: [Pt], dt: [Double], w: Int, h: Int, options: RefineOptions
    ) -> RefinedPath? {
        let n = chain.count
        guard n >= 6 else { return nil }

        func localWidth(_ p: Pt) -> Double {
            let xi = min(max(Int(p.x.rounded()), 0), w - 1)
            let yi = min(max(Int(p.y.rounded()), 0), h - 1)
            return 2 * dt[yi * w + xi]
        }
        // Moving-average the profile: raw dt jitters near junction remnants
        // and the offset sides would inherit every wiggle.
        let raw = chain.map { localWidth($0) }
        var ws = [Double](repeating: 0, count: n)
        let win = 3
        for i in 0..<n {
            var sum = 0.0
            var cnt = 0.0
            for j in max(0, i - win)...min(n - 1, i + win) {
                sum += raw[j]
                cnt += 1
            }
            ws[i] = sum / cnt
        }

        let sorted = ws.sorted()
        let p10 = sorted[n / 10]
        let p90 = sorted[min(n - 1, n * 9 / 10)]
        guard p10 > 0.5, p90 / p10 >= minRatio, p90 - p10 >= minSpreadPx else { return nil }

        // Offset both sides along the local normal.
        func normal(_ i: Int) -> Pt {
            let a = chain[max(0, i - 1)]
            let b = chain[min(n - 1, i + 1)]
            let dx = b.x - a.x
            let dy = b.y - a.y
            let len = (dx * dx + dy * dy).squareRoot()
            if len < 1e-9 { return Pt(0, 0) }
            return Pt(-dy / len, dx / len)
        }
        var left: [Pt] = []
        var right: [Pt] = []
        left.reserveCapacity(n)
        right.reserveCapacity(n)
        for i in 0..<n {
            let nrm = normal(i)
            let half = max(0.5, ws[i] / 2)
            left.append(Pt(chain[i].x + nrm.x * half, chain[i].y + nrm.y * half))
            right.append(Pt(chain[i].x - nrm.x * half, chain[i].y - nrm.y * half))
        }
        var ring = left
        ring.append(contentsOf: right.reversed())

        // Refine the ring like any closed boundary: DP-simplify then fit
        // lines/arcs/cubics, so the envelope exports as smooth geometry
        // instead of a per-pixel polygon.
        let simplified = Geometry.simplifyClosed(ring, epsilon: max(0.8, options.tolerance * 0.6))
        guard simplified.count >= 4 else { return nil }
        return PathRefine.refine(simplified, closed: true, options: options)
    }
}
