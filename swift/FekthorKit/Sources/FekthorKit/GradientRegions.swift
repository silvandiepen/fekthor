import Foundation

/// Moment-based gradient region segmentation (plan 05).
///
/// Each region's colour is modelled as **planar in x,y per RGB channel**
/// (`C(x,y) ≈ a·x + b·y + c`). A region that fits this model *is* a linear
/// gradient, so merge decisions minimise real gradient-fit error rather than raw
/// colour distance. Every region carries closed-form moments accumulated during
/// labelling; the plane-fit SSE follows in O(1) from those moments, and the
/// moments of a union are just element-wise sums — so evaluating a candidate
/// merge never touches a pixel. Greedy priority-queue agglomeration then merges
/// the cheapest adjacent pair while its per-pixel excess SSE stays under a
/// Blend-driven threshold, directly minimising the shape count for a given
/// fidelity (the core ask of plan 05).
public enum GradientRegions {
    /// Closed-form moments of one region. `add` forms a union's moments.
    /// Besides the planar terms, `q = x² + y²` moments extend the colour model
    /// to `C(x,y) ≈ a·x + b·y + d·q + e` — a radially symmetric paraboloid,
    /// the moment-space twin of the radial gradients `GradientFit` paints. A
    /// vignetted background or a shaded dome is quadratic, not planar; without
    /// the q term its quantized rings never merge and render as banding.
    struct Moments {
        var n = 0.0
        var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0, syy = 0.0
        var sq = 0.0, sqx = 0.0, sqy = 0.0, sqq = 0.0
        var sr = 0.0, srx = 0.0, sry = 0.0, srq = 0.0, srr = 0.0
        var sg = 0.0, sgx = 0.0, sgy = 0.0, sgq = 0.0, sgg = 0.0
        var sb = 0.0, sbx = 0.0, sby = 0.0, sbq = 0.0, sbb = 0.0

        @inline(__always) mutating func add(_ o: Moments) {
            n += o.n
            sx += o.sx; sy += o.sy; sxx += o.sxx; sxy += o.sxy; syy += o.syy
            sq += o.sq; sqx += o.sqx; sqy += o.sqy; sqq += o.sqq
            sr += o.sr; srx += o.srx; sry += o.sry; srq += o.srq; srr += o.srr
            sg += o.sg; sgx += o.sgx; sgy += o.sgy; sgq += o.sgq; sgg += o.sgg
            sb += o.sb; sbx += o.sbx; sby += o.sby; sbq += o.sbq; sbb += o.sbb
        }
    }

    /// SSE of the least-squares fit `c ≈ a·x + b·y + d·q + e` for one channel,
    /// from moments only (centred 3×3 normal equations). Falls back to the
    /// planar 2×2 solve when the q regressor is degenerate, then to the
    /// constant (mean-colour) fit when the region is collinear or tiny.
    @inline(__always)
    static func channelSSE(
        _ m: Moments,
        _ sc: Double, _ scx: Double, _ scy: Double, _ scq: Double, _ scc: Double,
        quad: Bool
    ) -> Double {
        let n = m.n
        if n < 1 { return 0 }
        let sccC = scc - sc * sc / n  // total centred sum of squares
        if n < 3 { return max(0, sccC) }
        let sxxC = m.sxx - m.sx * m.sx / n
        let sxyC = m.sxy - m.sx * m.sy / n
        let syyC = m.syy - m.sy * m.sy / n
        let det2 = sxxC * syyC - sxyC * sxyC
        if abs(det2) < 1e-6 { return max(0, sccC) }  // collinear → constant fit
        let scxC = scx - sc * m.sx / n
        let scyC = scy - sc * m.sy / n
        let planar: Double = {
            let a = (scxC * syyC - scyC * sxyC) / det2
            let b = (sxxC * scyC - sxyC * scxC) / det2
            return max(0, sccC - (a * scxC + b * scyC))
        }()
        if !quad || n < 5 { return planar }
        let sqxC = m.sqx - m.sq * m.sx / n
        let sqyC = m.sqy - m.sq * m.sy / n
        let sqqC = m.sqq - m.sq * m.sq / n
        // 3×3 determinant via cofactors of the symmetric normal matrix
        // [sxxC sxyC sqxC; sxyC syyC sqyC; sqxC sqyC sqqC].
        let c00 = syyC * sqqC - sqyC * sqyC
        let c01 = sxyC * sqqC - sqyC * sqxC
        let c02 = sxyC * sqyC - syyC * sqxC
        let det3 = sxxC * c00 - sxyC * c01 + sqxC * c02
        // Degenerate q regressor (e.g. thin ring where q is affine in x,y):
        // scale-relative test so huge coordinate sums don't mask rank loss.
        if abs(det3) < 1e-9 * max(1, abs(det2)) * max(1, sqqC) { return planar }
        let scqC = scq - sc * m.sq / n
        let m11 = sxxC * sqqC - sqxC * sqxC
        let m12 = sxxC * sqyC - sxyC * sqxC
        let a = (scxC * c00 - scyC * c01 + scqC * c02) / det3
        let b = (-scxC * c01 + scyC * m11 - scqC * m12) / det3
        let d = (scxC * c02 - scyC * m12 + scqC * det2) / det3
        let quad = max(0, sccC - (a * scxC + b * scyC + d * scqC))
        return min(planar, quad)
    }

    @inline(__always)
    static func sse(_ m: Moments, quad: Bool) -> Double {
        channelSSE(m, m.sr, m.srx, m.sry, m.srq, m.srr, quad: quad)
            + channelSSE(m, m.sg, m.sgx, m.sgy, m.sgq, m.sgg, quad: quad)
            + channelSSE(m, m.sb, m.sbx, m.sby, m.sbq, m.sbb, quad: quad)
    }

    /// Priority-queue entry: cost of merging roots `a<b`, tagged with the versions
    /// of both endpoints at push time so stale entries (endpoint since changed) are
    /// revalidated and skipped on pop. Ordering: cost, then the region-id pair —
    /// a deterministic tie-break (lowest id pair) as required by invariant #1.
    struct Entry {
        var cost: Double
        var a: Int
        var b: Int
        var va: Int
        var vb: Int
    }

    @inline(__always)
    static func less(_ x: Entry, _ y: Entry) -> Bool {
        if x.cost != y.cost { return x.cost < y.cost }
        if x.a != y.a { return x.a < y.a }
        return x.b < y.b
    }

    /// Minimal binary min-heap (no Foundation dep; deterministic order via `less`).
    struct Heap {
        var items: [Entry] = []
        var isEmpty: Bool { items.isEmpty }
        mutating func push(_ e: Entry) {
            items.append(e)
            var i = items.count - 1
            while i > 0 {
                let p = (i - 1) / 2
                if less(items[i], items[p]) {
                    items.swapAt(i, p)
                    i = p
                } else { break }
            }
        }
        mutating func pop() -> Entry? {
            if items.isEmpty { return nil }
            let top = items[0]
            let last = items.removeLast()
            if !items.isEmpty {
                items[0] = last
                var i = 0
                let n = items.count
                while true {
                    let l = 2 * i + 1
                    let r = 2 * i + 2
                    var m = i
                    if l < n, less(items[l], items[m]) { m = l }
                    if r < n, less(items[r], items[m]) { m = r }
                    if m == i { break }
                    items.swapAt(i, m)
                    i = m
                }
            }
            return top
        }
    }

    /// Segment a quantized image into gradient regions. Returns a per-pixel label
    /// map and one mean colour per label (largest-first ordering is applied later
    /// by `PlanarMap`). `tau` is the per-pixel excess-SSE merge threshold; border
    /// (image-edge-touching) regions get a `borderBias` cost multiplier when
    /// merging with each other so vignetted backgrounds coalesce into one shape.
    public static func segment(
        indices: [Int], palette: [RGB], img: RasterImage, width w: Int, height h: Int,
        minArea: Int, tau: Double, colorCap: Double = 200, borderBias: Double = 0.8
    ) -> (labels: [Int], colors: [RGB]) {
        let n = w * h
        var comp = [Int](repeating: -1, count: n)
        var moments: [Moments] = []
        var border: [Bool] = []

        img.data.withUnsafeBufferPointer { data in
            var stack: [Int] = []
            for start in 0..<n where comp[start] < 0 {
                let id = moments.count
                let target = indices[start]
                comp[start] = id
                stack.append(start)
                var m = Moments()
                var bord = false
                while let p = stack.popLast() {
                    let x = p % w
                    let y = p / w
                    let o = p * 4
                    let xr = Double(x), yr = Double(y)
                    let r = Double(data[o]), g = Double(data[o + 1]), b = Double(data[o + 2])
                    let q = xr * xr + yr * yr
                    m.n += 1
                    m.sx += xr; m.sy += yr
                    m.sxx += xr * xr; m.sxy += xr * yr; m.syy += yr * yr
                    m.sq += q; m.sqx += q * xr; m.sqy += q * yr; m.sqq += q * q
                    m.sr += r; m.srx += r * xr; m.sry += r * yr; m.srq += r * q; m.srr += r * r
                    m.sg += g; m.sgx += g * xr; m.sgy += g * yr; m.sgq += g * q; m.sgg += g * g
                    m.sb += b; m.sbx += b * xr; m.sby += b * yr; m.sbq += b * q; m.sbb += b * b
                    if x == 0 || y == 0 || x == w - 1 || y == h - 1 { bord = true }
                    if x > 0, comp[p - 1] < 0, indices[p - 1] == target {
                        comp[p - 1] = id
                        stack.append(p - 1)
                    }
                    if x < w - 1, comp[p + 1] < 0, indices[p + 1] == target {
                        comp[p + 1] = id
                        stack.append(p + 1)
                    }
                    if y > 0, comp[p - w] < 0, indices[p - w] == target {
                        comp[p - w] = id
                        stack.append(p - w)
                    }
                    if y < h - 1, comp[p + w] < 0, indices[p + w] == target {
                        comp[p + w] = id
                        stack.append(p + w)
                    }
                }
                moments.append(m)
                border.append(bord)
            }
        }
        let count = moments.count

        // Region adjacency (4-connected boundaries).
        var adj = [Set<Int>](repeating: [], count: count)
        for p in 0..<n {
            let x = p % w
            let y = p / w
            if x < w - 1, comp[p] != comp[p + 1] {
                adj[comp[p]].insert(comp[p + 1])
                adj[comp[p + 1]].insert(comp[p])
            }
            if y < h - 1, comp[p] != comp[p + w] {
                adj[comp[p]].insert(comp[p + w])
                adj[comp[p + w]].insert(comp[p])
            }
        }

        // Union-find; the lower id is always kept as the root (deterministic ids
        // for the PQ tie-break). `version[r]` bumps whenever r's moments change, so
        // heap entries tagged with an old version are revalidated away on pop.
        var parent = Array(0..<count)
        var version = [Int](repeating: 0, count: count)
        func find(_ x: Int) -> Int {
            var r = x
            while parent[r] != r { r = parent[r] }
            var c = x
            while parent[c] != c {
                let next = parent[c]
                parent[c] = r
                c = next
            }
            return r
        }
        func meanColor(_ r: Int) -> (Double, Double, Double) {
            let m = moments[r]
            return (m.sr / m.n, m.sg / m.n, m.sb / m.n)
        }
        // Merge b into a (caller guarantees a < b and both are roots).
        func union(_ a: Int, _ b: Int) {
            parent[b] = a
            moments[a].add(moments[b])
            border[a] = border[a] || border[b]
            adj[a].formUnion(adj[b])
            version[a] += 1
        }
        // Current-root neighbours, sorted (Set order is per-process random — the
        // sort restores determinism, invariant #1).
        func neighbors(_ r: Int) -> [Int] {
            var out = Set<Int>()
            for nb in adj[r] {
                let rn = find(nb)
                if rn != r { out.insert(rn) }
            }
            return out.sorted()
        }

        // Pre-pass: absorb sub-minArea regions into their most colour-similar
        // neighbour (area-only, as before). Border regions are exempt from being
        // absorbed away so a thin vignette rim is not eaten (plan 05 §3).
        if minArea > 0 {
            for _ in 0..<40 {
                var changed = false
                for c in 0..<count where find(c) == c && !border[c] && moments[c].n < Double(minArea) {
                    let nbs = neighbors(c)
                    if nbs.isEmpty { continue }
                    let cc = meanColor(c)
                    var best = -1
                    var bestd = Double.greatestFiniteMagnitude
                    for nb in nbs {
                        let d = ComponentMerge.dist2(cc, meanColor(nb))
                        if d < bestd || (d == bestd && nb < best) {
                            bestd = d
                            best = nb
                        }
                    }
                    if best >= 0 {
                        let lo = min(c, best), hi = max(c, best)
                        union(lo, hi)
                        changed = true
                    }
                }
                if !changed { break }
            }
        }

        // Excess SSE of forcing a and b onto one plane, normalised by the *smaller*
        // region's pixel count. Per-*union*-pixel (the plan's literal form) lets a
        // huge background cheaply absorb a small, differently-coloured object: its
        // few misfit pixels wash out across the union (thor's face merged into the
        // red backdrop). Dividing by min(n) keeps "big region eats small distinct
        // region" expensive — the small region's own pixels are badly fit — while
        // genuine shaded bands and the two halves of one smooth background still
        // merge cheaply. (Deviation from the plan's per-union-pixel formula — see
        // Attempts; the goal "background is one shape, distinct from the face" wins.)
        let cap2 = colorCap * colorCap
        func costOf(_ a: Int, _ b: Int) -> Double {
            // A generous hard colour cap only blocks the wildest cross-object merges
            // (kept high so it never fires on a single object's shading range).
            if ComponentMerge.dist2(meanColor(a), meanColor(b)) > cap2 {
                return .greatestFiniteMagnitude
            }
            var u = moments[a]
            u.add(moments[b])
            // The radial-quadratic model is reserved for border-touching pairs
            // (vignetted backgrounds — its motivation): on interior pairs the
            // paraboloid can bend to swallow a distinct neighbour (hair strands
            // absorbed into the face's shading).
            let quad = border[a] && border[b]
            let raw = sse(u, quad: quad) - sse(moments[a], quad: quad) - sse(moments[b], quad: quad)
            var c = raw / max(1, min(moments[a].n, moments[b].n))
            if border[a] && border[b] { c *= borderBias }
            return c
        }
        func pushCost(_ heap: inout Heap, _ a: Int, _ b: Int) {
            let lo = min(a, b), hi = max(a, b)
            let c = costOf(lo, hi)
            if c == .greatestFiniteMagnitude { return }  // colour-capped: never merge
            heap.push(Entry(cost: c, a: lo, b: hi, va: version[lo], vb: version[hi]))
        }

        // Greedy agglomeration.
        var heap = Heap()
        for c in 0..<count where find(c) == c {
            for nb in neighbors(c) where nb > c {
                pushCost(&heap, c, nb)
            }
        }
        while let e = heap.pop() {
            let a = e.a, b = e.b
            if find(a) != a || find(b) != b { continue }  // no longer roots
            if version[a] != e.va || version[b] != e.vb { continue }  // stale moments
            if a == b { continue }
            if e.cost > tau { break }  // heap min valid entry exceeds τ → done
            union(a, b)  // a < b, so a stays the root
            for nb in neighbors(a) where nb != a {
                pushCost(&heap, a, nb)
            }
        }

        // Relabel roots 0…m (first-appearance order — deterministic) and emit the
        // area-weighted mean colour per label.
        var rootLabel = [Int: Int](minimumCapacity: count)
        var colors: [RGB] = []
        var labels = [Int](repeating: 0, count: n)
        for p in 0..<n {
            let r = find(comp[p])
            if let l = rootLabel[r] {
                labels[p] = l
            } else {
                let l = colors.count
                rootLabel[r] = l
                labels[p] = l
                let c = meanColor(r)
                colors.append(
                    (
                        UInt8(min(255, max(0, c.0.rounded()))),
                        UInt8(min(255, max(0, c.1.rounded()))),
                        UInt8(min(255, max(0, c.2.rounded())))
                    ))
            }
        }
        return (labels, colors)
    }
}
