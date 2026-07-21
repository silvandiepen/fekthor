import XCTest

@testable import FekthorKit

final class RefineSharedChainTests: XCTestCase {
    /// Gap invariant (master plan §2): for a 2-colour image the two adjacent faces
    /// must reference the *same* refined shared boundary chain, so their geometry
    /// along the shared edge is point-identical (one traversed in reverse).
    func testSharedChainPointIdentical() {
        let w = 40, h = 40
        // Left half label 0, right half label 1 — one straight shared edge at x=20.
        var labels = [Int](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w where x >= 20 { labels[y * w + x] = 1 }
        }
        let opt = RefineOptions(tolerance: 1.5, cornerAngle: 32, straighten: 0.5, smoothing: 1)
        let faces = PlanarMap.faces(labels: labels, width: w, height: h, epsilon: 1.0, refine: opt)
        XCTAssertEqual(faces.count, 2)

        // Collect, per face, the flattened boundary points lying on the shared
        // edge (x ≈ 20).
        func sharedEdgePoints(_ face: PlanarMap.Face) -> [Pt] {
            var pts: [Pt] = []
            for rp in face.refined ?? [] {
                for p in PathRefine.flatten(rp) where abs(p.x - 20) < 0.01 {
                    pts.append(p)
                }
            }
            // Dedupe coincident samples (ring-start corner appears twice).
            var out: [Pt] = []
            for p in pts.sorted(by: { $0.y < $1.y })
            where out.last.map({ abs($0.y - p.y) > 1e-4 }) ?? true {
                out.append(p)
            }
            return out
        }
        let a = sharedEdgePoints(faces[0])
        let b = sharedEdgePoints(faces[1])
        XCTAssertFalse(a.isEmpty, "shared edge should be present in both faces")
        XCTAssertEqual(a.count, b.count, "both faces must sample the shared edge identically")
        // Both faces reference the one cached chain; geometry matches to float noise.
        for (pa, pb) in zip(a, b) {
            XCTAssertEqual(pa.x, pb.x, accuracy: 1e-6)
            XCTAssertEqual(pa.y, pb.y, accuracy: 1e-6)
        }
    }

    /// A refined chain and its reverse describe the same curve, so refining a
    /// chain the two possible ways yields point-identical geometry.
    func testReverseIsExactInverse() {
        var pts: [Pt] = []
        for i in 0..<24 { pts.append(Pt(Double(i), 4 * sin(Double(i) / 6))) }
        let opt = RefineOptions(tolerance: 1.0, cornerAngle: 32, straighten: 0.5, smoothing: 1)
        let forward = PathRefine.refine(pts, closed: false, options: opt)
        let backward = PathRefine.refine(pts.reversed(), closed: false, options: opt)
        let f = PathRefine.flatten(forward)
        let b = PathRefine.flatten(backward).reversed().map { $0 }
        XCTAssertEqual(f.count, b.count)
        for (pf, pb) in zip(f, b) {
            XCTAssertEqual(pf.x, pb.x, accuracy: 1e-6)
            XCTAssertEqual(pf.y, pb.y, accuracy: 1e-6)
        }
    }
}
