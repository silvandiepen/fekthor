import Foundation

/// Merge quantized regions into fewer, cleaner shapes.
///
/// Connected components of the colour-index map are merged when (a) an adjacent
/// pair has near-identical colour or (b) a component is smaller than a minimum
/// area — absorbed into its most colour-similar neighbour. Returns a per-pixel
/// component-label map plus one colour per label, ready for the planar map.
public enum ComponentMerge {
    @inline(__always)
    static func dist2(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        let dr = a.0 - b.0
        let dg = a.1 - b.1
        let db = a.2 - b.2
        return dr * dr + dg * dg + db * db
    }

    /// Region colour distance. At `flatten == 0` this is Euclidean RGB (unchanged,
    /// byte-identical). When flattening, region means convert to Oklab and use the
    /// single shared flatten metric (`colorThreshold` is then an Oklab-d² value).
    /// Region merging stays **adjacency-based** — only touching regions merge —
    /// unlike the global palette family clustering in `PaletteFamily`.
    @inline(__always)
    static func metric(
        _ a: (Double, Double, Double), _ b: (Double, Double, Double), flatten: Double
    ) -> Double {
        if flatten <= 0 { return dist2(a, b) }
        let la = OklabColor.from(r: a.0, g: a.1, b: a.2)
        let lb = OklabColor.from(r: b.0, g: b.1, b: b.2)
        return OklabColor.flattenDistance(la, lb, flatten: flatten)
    }

    public static func merge(
        indices: [Int], palette: [RGB], width w: Int, height h: Int,
        minArea: Int, colorThreshold: Double, flatten: Double = 0,
        distinctGuard: Double = .greatestFiniteMagnitude
    ) -> (labels: [Int], colors: [RGB]) {
        let n = w * h
        var comp = [Int](repeating: -1, count: n)
        var area: [Double] = []
        var sumR: [Double] = []
        var sumG: [Double] = []
        var sumB: [Double] = []

        // Connected components (4-connected) over the colour-index map.
        var stack: [Int] = []
        for start in 0..<n where comp[start] < 0 {
            let id = area.count
            let target = indices[start]
            let col = palette[target]
            area.append(0)
            sumR.append(0)
            sumG.append(0)
            sumB.append(0)
            comp[start] = id
            stack.append(start)
            while let p = stack.popLast() {
                area[id] += 1
                sumR[id] += Double(col.r)
                sumG[id] += Double(col.g)
                sumB[id] += Double(col.b)
                let x = p % w
                let y = p / w
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
        }
        let count = area.count

        // Union-find with area + colour sums, and an adjacency set per component.
        var parent = Array(0..<count)
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
        func color(_ r: Int) -> (Double, Double, Double) {
            (sumR[r] / area[r], sumG[r] / area[r], sumB[r] / area[r])
        }
        func union(_ a: Int, _ b: Int) {
            var ra = find(a)
            var rb = find(b)
            if ra == rb { return }
            if area[ra] < area[rb] { swap(&ra, &rb) }
            parent[rb] = ra
            area[ra] += area[rb]
            sumR[ra] += sumR[rb]
            sumG[ra] += sumG[rb]
            sumB[ra] += sumB[rb]
            adj[ra].formUnion(adj[rb])
        }
        func neighbors(_ r: Int) -> [Int] {
            var out = Set<Int>()
            for nb in adj[r] {
                let rn = find(nb)
                if rn != r { out.insert(rn) }
            }
            // Sorted: `Set` iteration order is per-process randomised (Swift seeds
            // its hasher per run), which would make the merge order — and thus the
            // output geometry — non-deterministic across processes. Invariant #1
            // (byte-identical output across runs) requires a stable order here.
            return out.sorted()
        }

        // Pass 1: merge adjacent components with near-identical colour.
        if colorThreshold > 0 {
            for _ in 0..<8 {
                var changed = false
                for c in 0..<count where find(c) == c {
                    for nb in neighbors(c) where nb > c {
                        if metric(color(c), color(nb), flatten: flatten) < colorThreshold {
                            union(c, nb)
                            changed = true
                        }
                    }
                }
                if !changed { break }
            }
        }

        // Pass 2: absorb small components into their most colour-similar neighbour.
        if minArea > 0 {
            for _ in 0..<40 {
                var changed = false
                for c in 0..<count where find(c) == c && area[c] < Double(minArea) {
                    let nbs = neighbors(c)
                    if nbs.isEmpty { continue }
                    var best = -1
                    var bestd = Double.greatestFiniteMagnitude
                    let cc = color(c)
                    for nb in nbs {
                        let d = metric(cc, color(nb), flatten: flatten)
                        if d < bestd {
                            bestd = d
                            best = nb
                        }
                    }
                    // Preserve intentional tiny details: if a component is far
                    // from every neighbour, area alone must not erase it. The
                    // configured threshold is squared RGB distance, so "3x" in
                    // colour distance is 9x here.
                    if colorThreshold >= 1500 && bestd > colorThreshold * 9 {
                        let currentRGB = rgb(cc)
                        let neighborRGB = nbs.map { rgb(color($0)) }
                        if !ColorQuantizer.isBlend(currentRGB, neighborRGB) { continue }
                    }
                    // Flatten distinct-colour guard: a small feature whose nearest
                    // neighbour is a different hue (black eyes ↔ skin, a red accent ↔
                    // its ground) stays — it survives any Flatten value (plan 04).
                    if flatten > 0 && bestd > distinctGuard { continue }
                    if best >= 0 {
                        union(c, best)
                        changed = true
                    }
                }
                if !changed { break }
            }
        }

        // A merged region's colour. flatten=0: the area-weighted RGB **mean**
        // (unchanged, byte-identical). flatten>0: the **dominant** source palette
        // entry — the flat family colour covering the most pixels (mode, not mean,
        // tie-break lower index), so a shade family never becomes a muddy average
        // (plan 07 §3). Built once per root from a pixel pass over the source index.
        var rootDominant: [Int: Int] = [:]
        if flatten > 0 {
            var rootCounts: [Int: [Int: Int]] = [:]
            for p in 0..<n {
                let r = find(comp[p])
                rootCounts[r, default: [:]][indices[p], default: 0] += 1
            }
            for (r, counts) in rootCounts {
                var bestIdx = Int.max
                var bestCount = -1
                for (idx, cnt) in counts {
                    if cnt > bestCount || (cnt == bestCount && idx < bestIdx) {
                        bestCount = cnt
                        bestIdx = idx
                    }
                }
                rootDominant[r] = bestIdx
            }
        }

        // Relabel roots to 0…m and emit one colour per label.
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
                if flatten > 0, let dom = rootDominant[r], dom >= 0, dom < palette.count {
                    colors.append(palette[dom])
                } else {
                    let c = color(r)
                    colors.append(
                        (
                            UInt8(min(255, max(0, c.0.rounded()))),
                            UInt8(min(255, max(0, c.1.rounded()))),
                            UInt8(min(255, max(0, c.2.rounded())))
                        ))
                }
            }
        }
        return (labels, colors)
    }

    static func rgb(_ c: (Double, Double, Double)) -> RGB {
        (
            UInt8(min(255, max(0, c.0.rounded()))),
            UInt8(min(255, max(0, c.1.rounded()))),
            UInt8(min(255, max(0, c.2.rounded())))
        )
    }
}
