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
}
