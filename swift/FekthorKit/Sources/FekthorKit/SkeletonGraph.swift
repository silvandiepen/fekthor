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
        // away-from-node direction at an edge end.
        func awayDir(_ e: [Pt], atStart: Bool) -> (Double, Double) {
            let k = min(e.count - 1, 4)
            if atStart { return unit(e[k].x - e[0].x, e[k].y - e[0].y) }
            let last = e.count - 1
            return unit(e[last - k].x - e[last].x, e[last - k].y - e[last].y)
        }

        var node: [Int: [(Int, Bool)]] = [:]
        for (i, e) in edges.enumerated() where e.count >= 2 {
            node[nkey(e.first!), default: []].append((i, true))
            node[nkey(e.last!), default: []].append((i, false))
        }
        var used = [Bool](repeating: false, count: edges.count)

        // Best straight continuation of travel direction `t` at node `nk`.
        func pick(_ nk: Int, _ t: (Double, Double)) -> (Int, Bool)? {
            guard let cands = node[nk] else { return nil }
            var best = -1
            var bestAtStart = true
            var bestDot = minCos
            for (ei, atStart) in cands where !used[ei] {
                let a = awayDir(edges[ei], atStart: atStart)
                let d = t.0 * a.0 + t.1 * a.1
                if d > bestDot {
                    bestDot = d
                    best = ei
                    bestAtStart = atStart
                }
            }
            return best >= 0 ? (best, bestAtStart) : nil
        }

        var result: [[Pt]] = []
        for start in 0..<edges.count where !used[start] && edges[start].count >= 2 {
            used[start] = true
            var chain = edges[start]
            // Extend at the end.
            while chain.count >= 2 {
                let k = min(chain.count - 1, 4)
                let last = chain.count - 1
                let t = unit(chain[last].x - chain[last - k].x, chain[last].y - chain[last - k].y)
                guard let (ei, atStart) = pick(nkey(chain[last]), t) else { break }
                used[ei] = true
                let e = edges[ei]
                chain.append(contentsOf: atStart ? Array(e.dropFirst()) : Array(e.reversed().dropFirst()))
            }
            // Extend at the start.
            while chain.count >= 2 {
                let k = min(chain.count - 1, 4)
                let t = unit(chain[0].x - chain[k].x, chain[0].y - chain[k].y)
                guard let (ei, atStart) = pick(nkey(chain[0]), t) else { break }
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
