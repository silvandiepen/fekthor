import Foundation

/// Convert a 1px skeleton into ordered graph edges (chains of pixels between
/// endpoints/junctions, plus isolated loops). Each edge becomes one path.
public enum SkeletonGraph {
    private static let offs = [
        (-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1),
    ]

    public static func edges(_ skel: Mask) -> [[Pt]] {
        let w = skel.width
        let h = skel.height
        let fg = skel.fg
        @inline(__always) func idx(_ x: Int, _ y: Int) -> Int { y * w + x }
        func neighbors(_ x: Int, _ y: Int) -> [(Int, Int)] {
            var r: [(Int, Int)] = []
            for (dx, dy) in offs {
                let nx = x + dx
                let ny = y + dy
                if nx >= 0, ny >= 0, nx < w, ny < h, fg[idx(nx, ny)] { r.append((nx, ny)) }
            }
            return r
        }
        @inline(__always) func key(_ a: Int, _ b: Int) -> UInt64 {
            (UInt64(a) << 32) | UInt64(b)
        }

        var visited = Set<UInt64>()
        var edges: [[Pt]] = []

        func walk(fromX x0: Int, fromY y0: Int, toX nx0: Int, toY ny0: Int, stopAtStart: Bool) {
            var path = [Pt(Double(x0), Double(y0)), Pt(Double(nx0), Double(ny0))]
            var px = x0
            var py = y0
            var cx = nx0
            var cy = ny0
            visited.insert(key(idx(px, py), idx(cx, cy)))
            visited.insert(key(idx(cx, cy), idx(px, py)))
            while true {
                if stopAtStart && cx == x0 && cy == y0 { break }
                let ns = neighbors(cx, cy)
                // For a chain interior we expect degree 2; stop at nodes/endpoints.
                if !stopAtStart && ns.count != 2 { break }
                var next: (Int, Int)? = nil
                for n in ns where !(n.0 == px && n.1 == py) {
                    if !visited.contains(key(idx(cx, cy), idx(n.0, n.1))) {
                        next = n
                        break
                    }
                }
                guard let nn = next else { break }
                visited.insert(key(idx(cx, cy), idx(nn.0, nn.1)))
                visited.insert(key(idx(nn.0, nn.1), idx(cx, cy)))
                path.append(Pt(Double(nn.0), Double(nn.1)))
                px = cx
                py = cy
                cx = nn.0
                cy = nn.1
            }
            edges.append(path)
        }

        // Node-anchored walks (endpoints and junctions).
        for y in 0..<h {
            for x in 0..<w where fg[idx(x, y)] {
                let deg = neighbors(x, y).count
                if deg == 2 || deg == 0 { continue }
                for (nx, ny) in neighbors(x, y) where !visited.contains(key(idx(x, y), idx(nx, ny))) {
                    walk(fromX: x, fromY: y, toX: nx, toY: ny, stopAtStart: false)
                }
            }
        }
        // Remaining pure loops (all degree 2, no node to anchor).
        for y in 0..<h {
            for x in 0..<w where fg[idx(x, y)] {
                for (nx, ny) in neighbors(x, y) where !visited.contains(key(idx(x, y), idx(nx, ny))) {
                    walk(fromX: x, fromY: y, toX: nx, toY: ny, stopAtStart: true)
                }
            }
        }
        return edges
    }

    /// Merge edges that continue straight through a junction into single
    /// strokes, so a line crossing another stays one path (drastically fewer,
    /// longer strokes). Edges are chained greedily by tangent continuity.
    public static func mergeByTangent(_ edges: [[Pt]], minCos: Double = 0.5) -> [[Pt]] {
        // minCos 0.5 (≤60° weld): a line genuinely passing through a crossing is
        // near-straight (cos ≈ 0.9+); permissive welds created dog-legged chains
        // whose fitted curves shortcut across occluding parts.
        func nkey(_ p: Pt) -> Int { Int(p.y.rounded()) * 100_000 + Int(p.x.rounded()) }
        func unit(_ ax: Double, _ ay: Double) -> (Double, Double) {
            let m = (ax * ax + ay * ay).squareRoot()
            return m < 1e-9 ? (0, 0) : (ax / m, ay / m)
        }
        // Tangent window at a polyline end: ~10px, so that at a shallow
        // X-crossing the window sees through the short shared middle segment.
        // That segment's own direction is the average of both crossing lines,
        // and a 4px window saw only that average — making the exit pick a coin
        // flip whose wrong outcome spliced the two lines into an S-bend.
        func windowEnd(_ pts: [Pt]) -> Int { min(pts.count - 1, 10) }
        func awayDir(_ e: [Pt], atStart: Bool) -> (Double, Double) {
            let k = windowEnd(e)
            if atStart { return unit(e[k].x - e[0].x, e[k].y - e[0].y) }
            let last = e.count - 1
            return unit(e[last - k].x - e[last].x, e[last - k].y - e[last].y)
        }

        // A skeleton junction is usually a small CLUSTER of adjacent node
        // pixels, so the four ends of an X-crossing land on different exact
        // pixels. Exact-pixel grouping then hides the collinear continuation
        // from `pick`, welding a line with its oblique crosser instead (the
        // S-bend artifact). Union node keys within a 2px Chebyshev radius so
        // every end at one visual junction competes in the same pool.
        var rawNode: [Int: [(Int, Bool)]] = [:]
        for (i, e) in edges.enumerated() where e.count >= 2 {
            rawNode[nkey(e.first!), default: []].append((i, true))
            rawNode[nkey(e.last!), default: []].append((i, false))
        }
        var parent: [Int: Int] = [:]
        func findRoot(_ k: Int) -> Int {
            var r = k
            while let p = parent[r], p != r { r = p }
            var c = k
            while let p = parent[c], p != c {
                parent[c] = r
                c = p
            }
            return r
        }
        for k in rawNode.keys.sorted() { parent[k] = k }
        for k in rawNode.keys.sorted() {
            let ky = k / 100_000
            let kx = k % 100_000
            for dy in -1...1 {
                for dx in -1...1 where dx != 0 || dy != 0 {
                    let nk = (ky + dy) * 100_000 + (kx + dx)
                    if parent[nk] != nil {
                        let ra = findRoot(k)
                        let rb = findRoot(nk)
                        if ra != rb { parent[max(ra, rb)] = min(ra, rb) }
                    }
                }
            }
        }
        var node: [Int: [(Int, Bool)]] = [:]
        for k in rawNode.keys.sorted() {
            node[findRoot(k), default: []].append(contentsOf: rawNode[k]!)
        }
        let clusterOf: (Pt) -> Int = { p in findRoot(nkey(p)) }
        var used = [Bool](repeating: false, count: edges.count)

        // Signed curvature (mean turn per px) traversing an edge end away from
        // the node. A curve crossed by its own tangent line has the same *angle*
        // continuation both ways — only curvature continuity tells the curve's
        // far side (keeps bending) from the straight line (κ ≈ 0).
        func curvAway(_ e: [Pt], atStart: Bool) -> Double {
            let k = min(e.count - 1, 8)
            if k < 2 { return 0 }
            var pts: [Pt] = []
            pts.reserveCapacity(k + 1)
            if atStart {
                for i in 0...k { pts.append(e[i]) }
            } else {
                let last = e.count - 1
                for i in 0...k { pts.append(e[last - i]) }
            }
            var turn = 0.0
            var len = 0.0
            for i in 1..<pts.count {
                let dx = pts[i].x - pts[i - 1].x
                let dy = pts[i].y - pts[i - 1].y
                len += (dx * dx + dy * dy).squareRoot()
                if i >= 2 {
                    let px = pts[i - 1].x - pts[i - 2].x
                    let py = pts[i - 1].y - pts[i - 2].y
                    turn += atan2(px * dy - py * dx, px * dx + py * dy)
                }
            }
            return len < 1e-9 ? 0 : turn / len
        }
        // Curvature-mismatch weight in dot-score units (κ in rad/px; a 0.03
        // rad/px mismatch — a tight curve vs a straight — costs 0.24).
        let curvWeight = 8.0

        // Best continuation of travel direction `t` (curvature `kt`) at node
        // `nk`, scored by tangent dot minus curvature mismatch. A weld is
        // refused when some other free end at the node continues into the
        // winner with a better score — greedy chain order must not let an
        // oblique chain steal a collinear pair (stripes spliced into S-bends).
        func pick(_ nk: Int, _ t: (Double, Double), _ kt: Double) -> (Int, Bool)? {
            guard let cands = node[nk] else { return nil }
            var best = -1
            var bestAtStart = true
            var bestScore = -Double.infinity
            var bestDot = 0.0
            for (ei, atStart) in cands where !used[ei] {
                // A short fragment whose other end is in the SAME cluster is
                // junction debris; welding it turns the chain back into the
                // cluster and chains of such debris render as scribble blobs.
                // Only fragments that exit the cluster continue the stroke.
                let e = edges[ei]
                if e.count < 10 {
                    let other = atStart ? e.last! : e.first!
                    if findRoot(nkey(other)) == nk { continue }
                }
                let a = awayDir(e, atStart: atStart)
                let d = t.0 * a.0 + t.1 * a.1
                if d <= minCos { continue }
                // Two near-straight pieces meeting at a real angle must stay
                // two strokes: welding them hands the smoother a sub-corner
                // bend it renders as an S-swoop. Genuinely continuing straight
                // lines score ~0.97; only curved ends need the permissive
                // threshold (their tangents legitimately disagree).
                let candKappa = curvAway(e, atStart: atStart)
                if abs(kt) < 0.008, abs(candKappa) < 0.008, d < 0.9 { continue }
                // `kt` is the chain's curvature along its travel direction;
                // the continuation, travelling on away from the node, keeps
                // the same turn sign, so continuity is a direct difference.
                let score = d - curvWeight * abs(kt - candKappa)
                if score > bestScore {
                    bestScore = score
                    bestDot = d
                    best = ei
                    bestAtStart = atStart
                }
            }
            if best < 0 || bestDot <= minCos { return nil }
            let bestAway = awayDir(edges[best], atStart: bestAtStart)
            let bestCurv = curvAway(edges[best], atStart: bestAtStart)
            // Only substantial rivals veto: a 2-3px junction fragment's
            // direction is angle noise, not evidence of a straighter pair.
            for (ri, rAtStart) in cands where !used[ri] && ri != best && edges[ri].count >= 5 {
                let ra = awayDir(edges[ri], atStart: rAtStart)
                // Rival travel direction into the node is -awayDir.
                let rivalDot = -(ra.0 * bestAway.0 + ra.1 * bestAway.1)
                let rivalScore =
                    rivalDot - curvWeight * abs(curvAway(edges[ri], atStart: rAtStart) + bestCurv)
                if rivalScore > bestScore + 1e-9 { return nil }
            }
            return (best, bestAtStart)
        }

        // Chain-end curvature travelling toward the given end.
        func chainCurv(_ chain: [Pt], towardEnd: Bool) -> Double {
            -curvAway(chain, atStart: !towardEnd)
        }

        var result: [[Pt]] = []
        for start in 0..<edges.count where !used[start] && edges[start].count >= 2 {
            used[start] = true
            var chain = edges[start]
            // Extend at the end.
            while chain.count >= 2 {
                let k = windowEnd(chain)
                let last = chain.count - 1
                let t = unit(chain[last].x - chain[last - k].x, chain[last].y - chain[last - k].y)
                let kt = chainCurv(chain, towardEnd: true)
                guard let (ei, atStart) = pick(clusterOf(chain[last]), t, kt) else { break }
                used[ei] = true
                let e = edges[ei]
                chain.append(contentsOf: atStart ? Array(e.dropFirst()) : Array(e.reversed().dropFirst()))
            }
            // Extend at the start.
            while chain.count >= 2 {
                let k = windowEnd(chain)
                let t = unit(chain[0].x - chain[k].x, chain[0].y - chain[k].y)
                let kt = chainCurv(chain, towardEnd: false)
                guard let (ei, atStart) = pick(clusterOf(chain[0]), t, kt) else { break }
                used[ei] = true
                let e = edges[ei]
                let piece = atStart ? Array(e.dropFirst()) : Array(e.reversed().dropFirst())
                chain.insert(contentsOf: piece.reversed(), at: 0)
            }
            result.append(chain)
        }
        return result
    }
}
