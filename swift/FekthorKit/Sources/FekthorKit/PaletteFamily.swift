import Foundation

/// Flatten's colour-reduction step (plan 07): collapse **shade families**.
///
/// The engine quantises *fine* first (many colours, one per shade band), then
/// this reduces the palette to the user's Colours count by **complete-linkage
/// agglomerative clustering under the flatten metric** — never by re-running
/// k-means at a lower k (which would merge across hues in RGB and make mud).
///
/// Asymmetry (documented deliberately): this palette-level clustering is
/// **global** — that is what "reduce colours" means, two beard blonds merge
/// wherever they sit. Region merging (`ComponentMerge`) stays **adjacency-based**
/// — only touching regions merge. The two work together but at different levels.
enum PaletteFamily {
    /// Reduce `q`'s palette to `targetColors` families, remapping every pixel to
    /// its family's dominant-shade representative colour.
    ///
    /// - `flatten`: 0…1, drives the metric weights (see `OklabColor`).
    /// - `separation`: a hard floor in flatten-d² units. Two families never merge
    ///   once every remaining pair is farther apart than this, even if that leaves
    ///   more than `targetColors` — this is plan 04's distinct-colour guard at the
    ///   palette level (a tiny red dot on white survives any Flatten value).
    static func reduce(_ q: Quantized, targetColors: Int, flatten: Double, separation: Double)
        -> Quantized
    {
        let m = q.palette.count
        guard m > 1, targetColors >= 1, targetColors < m else { return q }

        // Per-entry pixel coverage (area-weighted mode input) — deterministic.
        var coverage = [Int](repeating: 0, count: m)
        for idx in q.indices where idx >= 0 && idx < m { coverage[idx] += 1 }

        let lab = q.palette.map { OklabColor.from($0) }

        // Clusters as sorted member-index lists; distances are complete-linkage
        // (the max pairwise flatten distance between the two clusters' members).
        var clusters: [[Int]] = (0..<m).map { [$0] }

        @inline(__always)
        func completeLinkage(_ a: [Int], _ b: [Int]) -> Double {
            var worst = 0.0
            for i in a {
                for j in b {
                    let d = OklabColor.flattenDistance(lab[i], lab[j], flatten: flatten)
                    if d > worst { worst = d }
                }
            }
            return worst
        }

        while clusters.count > targetColors {
            var bestD = Double.greatestFiniteMagnitude
            var bestI = -1
            var bestJ = -1
            for i in 0..<clusters.count {
                for j in (i + 1)..<clusters.count {
                    let d = completeLinkage(clusters[i], clusters[j])
                    // Tie-break on cluster order (which is anchored to lowest member
                    // palette index below), so the merge sequence is deterministic.
                    if d < bestD {
                        bestD = d
                        bestI = i
                        bestJ = j
                    }
                }
            }
            if bestI < 0 { break }
            // Distinct-colour guard: stop before merging genuinely different hues.
            if bestD > separation { break }
            var merged = clusters[bestI] + clusters[bestJ]
            merged.sort()
            clusters.remove(at: bestJ)
            clusters.remove(at: bestI)
            clusters.append(merged)
            // Re-anchor ordering by lowest member index for stable labels/tie-breaks.
            clusters.sort { ($0.first ?? 0) < ($1.first ?? 0) }
        }

        // Representative = the member entry with the largest coverage (mode, not
        // mean); tie-break the lower palette index. Plan 04's exact-colour rule
        // then already holds — the representative *is* a real palette entry, which
        // quantizeAuto stored as the exact source colour on the logo path.
        var oldToNew = [Int](repeating: 0, count: m)
        var palette: [RGB] = []
        palette.reserveCapacity(clusters.count)
        for (label, members) in clusters.enumerated() {
            var repIdx = members[0]
            for member in members {
                if coverage[member] > coverage[repIdx]
                    || (coverage[member] == coverage[repIdx] && member < repIdx)
                {
                    repIdx = member
                }
            }
            palette.append(q.palette[repIdx])
            for member in members { oldToNew[member] = label }
        }

        var indices = q.indices
        for i in 0..<indices.count {
            let old = indices[i]
            indices[i] = (old >= 0 && old < m) ? oldToNew[old] : 0
        }

        return Quantized(
            width: q.width, height: q.height, palette: palette, indices: indices,
            paletteExactCount: min(q.paletteExactCount, palette.count))
    }
}
