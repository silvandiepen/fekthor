import Foundation

/// Zhang-Suen thinning: reduce a foreground mask to a 1px-wide skeleton.
/// Topology-preserving and deterministic (docs O-002).
public enum Skeleton {
    public static func thin(_ mask: Mask) -> Mask {
        let w = mask.width
        let h = mask.height
        var g = mask.fg.map { $0 ? UInt8(1) : UInt8(0) }
        @inline(__always) func idx(_ x: Int, _ y: Int) -> Int { y * w + x }
        @inline(__always) func get(_ x: Int, _ y: Int) -> UInt8 {
            if x < 0 || y < 0 || x >= w || y >= h { return 0 }
            return g[idx(x, y)]
        }

        var changed = true
        while changed {
            changed = false
            for step in 0..<2 {
                var toDelete: [Int] = []
                for y in 0..<h {
                    for x in 0..<w where g[idx(x, y)] == 1 {
                        let p2 = get(x, y - 1)
                        let p3 = get(x + 1, y - 1)
                        let p4 = get(x + 1, y)
                        let p5 = get(x + 1, y + 1)
                        let p6 = get(x, y + 1)
                        let p7 = get(x - 1, y + 1)
                        let p8 = get(x - 1, y)
                        let p9 = get(x - 1, y - 1)
                        let neigh = [p2, p3, p4, p5, p6, p7, p8, p9]
                        let b = Int(neigh.reduce(0, +))
                        if b < 2 || b > 6 { continue }
                        var a = 0
                        for k in 0..<8 where neigh[k] == 0 && neigh[(k + 1) % 8] == 1 { a += 1 }
                        if a != 1 { continue }
                        let c1: UInt8
                        let c2: UInt8
                        if step == 0 {
                            c1 = p2 * p4 * p6
                            c2 = p4 * p6 * p8
                        } else {
                            c1 = p2 * p4 * p8
                            c2 = p2 * p6 * p8
                        }
                        if c1 == 0 && c2 == 0 { toDelete.append(idx(x, y)) }
                    }
                }
                if !toDelete.isEmpty {
                    changed = true
                    for i in toDelete { g[i] = 0 }
                }
            }
        }

        return Mask(width: w, height: h, fg: g.map { $0 == 1 })
    }
}
