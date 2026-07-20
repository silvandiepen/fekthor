import Foundation

/// Extract the faces of a labelled image as a planar subdivision.
///
/// Region boundaries live on the pixel-corner "crack" grid. Boundaries are split
/// at junctions (grid points where ≠2 cracks meet) into chains; each chain is
/// simplified **once** and shared by both adjacent regions. Adjacent faces
/// therefore use identical boundary points — no gaps or overlaps — and the
/// per-chain Douglas-Peucker removes staircase jitter (topology-aware, D-002/D-017).
public enum PlanarMap {
    /// Returns one entry per label with its even-odd fill rings, largest first.
    public static func faces(labels: [Int], width w: Int, height h: Int, epsilon: Double)
        -> [(label: Int, rings: [[Pt]])]
    {
        let W = w + 1
        @inline(__always) func lbl(_ x: Int, _ y: Int) -> Int {
            (x < 0 || y < 0 || x >= w || y >= h) ? -1 : labels[y * w + x]
        }
        let dgx = [0, 1, 0, -1]
        let dgy = [-1, 0, 1, 0]
        // Directions: 0=N, 1=E, 2=S, 3=W.
        @inline(__always) func edge(_ gx: Int, _ gy: Int, _ d: Int) -> Bool {
            switch d {
            case 0: return gy > 0 && lbl(gx - 1, gy - 1) != lbl(gx, gy - 1)
            case 1: return gx < w && lbl(gx, gy - 1) != lbl(gx, gy)
            case 2: return gy < h && lbl(gx - 1, gy) != lbl(gx, gy)
            case 3: return gx > 0 && lbl(gx - 1, gy - 1) != lbl(gx - 1, gy)
            default: return false
            }
        }
        @inline(__always) func leftLabel(_ gx: Int, _ gy: Int, _ d: Int) -> Int {
            switch d {
            case 0: return lbl(gx - 1, gy - 1)
            case 1: return lbl(gx, gy - 1)
            case 2: return lbl(gx, gy)
            case 3: return lbl(gx - 1, gy)
            default: return -1
            }
        }
        @inline(__always) func degree(_ gx: Int, _ gy: Int) -> Int {
            var c = 0
            for d in 0..<4 where edge(gx, gy, d) { c += 1 }
            return c
        }
        @inline(__always) func gpIndex(_ gx: Int, _ gy: Int) -> Int { gy * W + gx }
        @inline(__always) func coord(_ gi: Int) -> (Int, Int) { (gi % W, gi / W) }
        func toPt(_ gi: Int) -> Pt {
            let (x, y) = coord(gi)
            return Pt(Double(x), Double(y))
        }
        @inline(__always) func isNode(_ gi: Int) -> Bool {
            let (x, y) = coord(gi)
            return degree(x, y) != 2
        }

        // Trace every face loop with the region kept on the left.
        var visited = [Bool](repeating: false, count: W * (h + 1) * 4)
        var loops: [(label: Int, pts: [Int])] = []
        for gy in 0...h {
            for gx in 0...w {
                for d in 0..<4 where edge(gx, gy, d) {
                    if visited[gpIndex(gx, gy) * 4 + d] { continue }
                    let face = leftLabel(gx, gy, d)
                    var pts: [Int] = []
                    var cx = gx, cy = gy, cd = d
                    while true {
                        let id = gpIndex(cx, cy) * 4 + cd
                        if visited[id] { break }
                        visited[id] = true
                        pts.append(gpIndex(cx, cy))
                        let nx = cx + dgx[cd]
                        let ny = cy + dgy[cd]
                        var nd = -1
                        // Left, straight, right, back — hug the left face.
                        for turn in [3, 0, 1, 2] {
                            let cand = (cd + turn) % 4
                            if edge(nx, ny, cand) {
                                nd = cand
                                break
                            }
                        }
                        if nd == -1 { break }
                        cx = nx
                        cy = ny
                        cd = nd
                    }
                    if face != -1 && pts.count >= 2 { loops.append((face, pts)) }
                }
            }
        }

        // Shared per-chain simplification cache.
        struct Key: Hashable {
            let a: Int
            let b: Int
            let n: Int
            let s: Int
            let x: Int
        }
        var cache: [Key: [Pt]] = [:]

        func simplifyOpenChain(_ chain: [Int]) -> [Pt] {
            let a = chain.first!
            let b = chain.last!
            var s = 0
            var x = 0
            if chain.count > 2 {
                for gi in chain[1..<(chain.count - 1)] {
                    s += gi
                    x ^= gi
                }
            }
            let key = Key(a: min(a, b), b: max(a, b), n: chain.count, s: s, x: x)
            if let c = cache[key] { return a <= b ? c : Array(c.reversed()) }
            let canonical = a <= b ? chain : chain.reversed()
            let simp = Geometry.simplifyOpen(canonical.map(toPt), epsilon: epsilon)
            cache[key] = simp
            return a <= b ? simp : Array(simp.reversed())
        }

        func simplifyClosedCycle(_ cyc: [Int]) -> [Pt] {
            var s = 0
            var x = 0
            for gi in cyc {
                s += gi
                x ^= gi
            }
            let mn = cyc.min()!
            let key = Key(a: mn, b: mn, n: cyc.count, s: s, x: x)
            if let c = cache[key] { return c }
            let idx = cyc.firstIndex(of: mn)!
            let rotated = Array(cyc[idx...] + cyc[..<idx])
            let simp = Geometry.simplifyClosed(rotated.map(toPt), epsilon: epsilon)
            cache[key] = simp
            return simp
        }

        // Assemble each loop into a ring using shared simplified chains.
        var perLabel: [Int: [[Pt]]] = [:]
        for loop in loops {
            let pts = loop.pts
            let n = pts.count
            var ring: [Pt] = []
            let nodePositions = pts.indices.filter { isNode(pts[$0]) }
            if nodePositions.isEmpty {
                ring = simplifyClosedCycle(pts)
            } else {
                let start = nodePositions.first!
                var chains: [[Int]] = []
                var cur = [pts[start]]
                var i = (start + 1) % n
                while true {
                    cur.append(pts[i])
                    if isNode(pts[i]) {
                        chains.append(cur)
                        cur = [pts[i]]
                    }
                    if i == start { break }
                    i = (i + 1) % n
                }
                for ch in chains where ch.count >= 2 {
                    let simp = simplifyOpenChain(ch)
                    if ring.isEmpty {
                        ring.append(contentsOf: simp)
                    } else {
                        ring.append(contentsOf: simp.dropFirst())
                    }
                }
                if ring.count > 1, ring.first! == ring.last! { ring.removeLast() }
            }
            if ring.count >= 3 { perLabel[loop.label, default: []].append(ring) }
        }

        var result: [(label: Int, rings: [[Pt]])] = perLabel.map { ($0.key, $0.value) }
        func maxArea(_ rings: [[Pt]]) -> Double { rings.map { Geometry.area($0) }.max() ?? 0 }
        result.sort { maxArea($0.rings) > maxArea($1.rings) }
        return result
    }
}
