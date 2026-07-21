import Foundation

/// Extract the faces of a labelled image as a planar subdivision.
///
/// Region boundaries live on the pixel-corner "crack" grid. Boundaries are split
/// at junctions (grid points where ≠2 cracks meet) into chains; each chain is
/// simplified **once** and shared by both adjacent regions. Adjacent faces
/// therefore use identical boundary points — no gaps or overlaps — and the
/// per-chain Douglas-Peucker removes staircase jitter (topology-aware, D-002/D-017).
public enum PlanarMap {
    /// One face: its even-odd polygonal rings, and — when refinement was
    /// requested — the shared-chain refined ring paths (plan 02). Both faces of a
    /// shared boundary reference the *same* cached refined chain (reversed for the
    /// opposite traversal), so adjacent fills stay point-identical (invariant #2).
    public typealias Face = (label: Int, rings: [[Pt]], refined: [RefinedPath]?)

    /// Legacy convenience: rings only, no refinement.
    public static func faces(labels: [Int], width w: Int, height h: Int, epsilon: Double)
        -> [(label: Int, rings: [[Pt]])]
    {
        faces(labels: labels, width: w, height: h, epsilon: epsilon, refine: nil)
            .map { ($0.label, $0.rings) }
    }

    /// Returns one entry per label with its even-odd fill rings, largest first.
    /// When `refine` is set, each shared boundary chain is refined once (cached by
    /// canonical form) and the refined ring paths are returned alongside.
    public static func faces(
        labels: [Int], width w: Int, height h: Int, epsilon: Double, refine: RefineOptions?
    ) -> [Face] {
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

        // Shared per-chain cache. Keyed on the canonical (direction-independent)
        // form so both faces of a boundary get the identical refined/simplified
        // chain — the gap-freedom invariant (master plan §2).
        struct Key: Hashable {
            let a: Int
            let b: Int
            let n: Int
            let s: Int
            let x: Int
        }
        var cache: [Key: [Pt]] = [:]
        var refineCache: [Key: RefinedPath] = [:]

        func openKey(_ chain: [Int]) -> Key {
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
            return Key(a: min(a, b), b: max(a, b), n: chain.count, s: s, x: x)
        }

        func simplifyOpenChain(_ chain: [Int]) -> [Pt] {
            let a = chain.first!
            let b = chain.last!
            let key = openKey(chain)
            if let c = cache[key] { return a <= b ? c : Array(c.reversed()) }
            let canonical = a <= b ? chain : chain.reversed()
            let simp = Geometry.simplifyOpen(canonical.map(toPt), epsilon: epsilon)
            cache[key] = simp
            return a <= b ? simp : Array(simp.reversed())
        }

        func refineOpenChain(_ chain: [Int], _ opt: RefineOptions) -> RefinedPath {
            let a = chain.first!
            let b = chain.last!
            let key = openKey(chain)
            if let c = refineCache[key] { return a <= b ? c : PathRefine.reverse(c) }
            let canonical = a <= b ? chain : chain.reversed()
            // Denoise only the pixel-staircase (half-pixel jitter) with a light DP,
            // then fit typed segments to the near-dense result so curves hug the
            // true boundary (not a lossy DP polyline) — high fidelity, few nodes.
            let dense = Geometry.simplifyOpen(canonical.map(toPt), epsilon: 0.6)
            let rp = PathRefine.refine(dense, closed: false, options: opt)
            refineCache[key] = rp
            return a <= b ? rp : PathRefine.reverse(rp)
        }

        func closedKey(_ cyc: [Int]) -> (Key, Int) {
            var s = 0
            var x = 0
            for gi in cyc {
                s += gi
                x ^= gi
            }
            let mn = cyc.min()!
            return (Key(a: mn, b: mn, n: cyc.count, s: s, x: x), mn)
        }

        func simplifyClosedCycle(_ cyc: [Int]) -> [Pt] {
            let (key, mn) = closedKey(cyc)
            if let c = cache[key] { return c }
            let idx = cyc.firstIndex(of: mn)!
            let rotated = Array(cyc[idx...] + cyc[..<idx])
            let simp = Geometry.simplifyClosed(rotated.map(toPt), epsilon: epsilon)
            cache[key] = simp
            return simp
        }

        func refineClosedCycle(_ cyc: [Int], _ opt: RefineOptions) -> RefinedPath {
            let (key, mn) = closedKey(cyc)
            if let c = refineCache[key] { return c }
            let idx = cyc.firstIndex(of: mn)!
            let rotated = Array(cyc[idx...] + cyc[..<idx])
            let dense = Geometry.simplifyClosed(rotated.map(toPt), epsilon: 0.6)
            let rp = PathRefine.refine(dense, closed: true, options: opt)
            refineCache[key] = rp
            return rp
        }

        // Assemble each loop into a ring using shared chains. When refining, the
        // ring's polygon (`rings`) is the flattened refined path so area/bbox stay
        // consistent with what is rendered.
        var perLabel: [Int: [[Pt]]] = [:]
        var perLabelRefined: [Int: [RefinedPath]] = [:]
        for loop in loops {
            let pts = loop.pts
            let n = pts.count
            let nodePositions = pts.indices.filter { isNode(pts[$0]) }

            if let opt = refine {
                var ringPath: RefinedPath?
                if nodePositions.isEmpty {
                    ringPath = refineClosedCycle(pts, opt)
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
                        let rp = refineOpenChain(ch, opt)
                        if ringPath == nil {
                            ringPath = rp
                        } else {
                            ringPath!.segments.append(contentsOf: rp.segments)
                        }
                    }
                    ringPath?.closed = true
                }
                if let rp = ringPath, rp.segments.count >= 2 {
                    let poly = PathRefine.flatten(rp)
                    if poly.count >= 3 {
                        perLabel[loop.label, default: []].append(poly)
                        perLabelRefined[loop.label, default: []].append(rp)
                    }
                }
                continue
            }

            // Legacy (no refinement): DP-simplified polygon rings only.
            var ring: [Pt] = []
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

        var result: [Face] = perLabel.map { ($0.key, $0.value, perLabelRefined[$0.key]) }
        func maxArea(_ rings: [[Pt]]) -> Double { rings.map { Geometry.area($0) }.max() ?? 0 }
        // `perLabel` is a Dictionary (random iteration order per process); the sort
        // needs a total order with a stable tie-breaker on label, or equal-area
        // faces would order differently each run and break invariant #1.
        result.sort {
            let a = maxArea($0.rings), b = maxArea($1.rings)
            if a != b { return a > b }
            return $0.label < $1.label
        }
        return result
    }

    /// Extract the interior boundary lines between regions (the "coloring plate"):
    /// each boundary between two regions is traced once and shared, and the image
    /// frame (region-vs-outside) is excluded. Used by Strokes on colour images.
    public static func boundaryChains(labels: [Int], width w: Int, height h: Int, epsilon: Double)
        -> [[Pt]]
    {
        let W = w + 1
        @inline(__always) func lbl(_ x: Int, _ y: Int) -> Int {
            (x < 0 || y < 0 || x >= w || y >= h) ? -1 : labels[y * w + x]
        }
        let dgx = [0, 1, 0, -1]
        let dgy = [-1, 0, 1, 0]
        // Interior boundary only: both separated pixels in-bounds and different.
        @inline(__always) func edgeB(_ gx: Int, _ gy: Int, _ d: Int) -> Bool {
            let ax: Int, ay: Int, bx: Int, by: Int
            switch d {
            case 0: (ax, ay, bx, by) = (gx - 1, gy - 1, gx, gy - 1)
            case 1: (ax, ay, bx, by) = (gx, gy - 1, gx, gy)
            case 2: (ax, ay, bx, by) = (gx - 1, gy, gx, gy)
            default: (ax, ay, bx, by) = (gx - 1, gy - 1, gx - 1, gy)
            }
            let la = lbl(ax, ay)
            let lb = lbl(bx, by)
            return la != -1 && lb != -1 && la != lb
        }
        @inline(__always) func degreeB(_ gx: Int, _ gy: Int) -> Int {
            var c = 0
            for d in 0..<4 where edgeB(gx, gy, d) { c += 1 }
            return c
        }
        @inline(__always) func key(_ gx: Int, _ gy: Int, _ d: Int) -> Int { (gy * W + gx) * 4 + d }
        func toPt(_ gx: Int, _ gy: Int) -> Pt { Pt(Double(gx), Double(gy)) }

        var visited = Set<Int>()
        func walk(_ sx: Int, _ sy: Int, _ sd: Int) -> [Pt] {
            var pts: [Pt] = [toPt(sx, sy)]
            var cx = sx, cy = sy, cd = sd
            while true {
                let hid = key(cx, cy, cd)
                if visited.contains(hid) { break }
                let nx = cx + dgx[cd]
                let ny = cy + dgy[cd]
                visited.insert(hid)
                visited.insert(key(nx, ny, (cd + 2) % 4))
                pts.append(toPt(nx, ny))
                if degreeB(nx, ny) != 2 { break }
                let rev = (cd + 2) % 4
                var nd = -1
                for dd in 0..<4 where dd != rev && edgeB(nx, ny, dd) {
                    nd = dd
                    break
                }
                if nd == -1 { break }
                cx = nx
                cy = ny
                cd = nd
            }
            return pts
        }

        var chains: [[Pt]] = []
        // Chains anchored at junctions/ends first.
        for gy in 0...h {
            for gx in 0...w {
                let deg = degreeB(gx, gy)
                if deg == 2 || deg == 0 { continue }
                for d in 0..<4 where edgeB(gx, gy, d) && !visited.contains(key(gx, gy, d)) {
                    let pts = walk(gx, gy, d)
                    if pts.count >= 2 {
                        chains.append(Geometry.simplifyOpen(pts, epsilon: epsilon))
                    }
                }
            }
        }
        // Remaining closed loops (no junction).
        for gy in 0...h {
            for gx in 0...w {
                for d in 0..<4 where edgeB(gx, gy, d) && !visited.contains(key(gx, gy, d)) {
                    let pts = walk(gx, gy, d)
                    if pts.count >= 3 {
                        chains.append(Geometry.simplifyClosed(pts, epsilon: epsilon))
                    }
                }
            }
        }
        return chains
    }
}
