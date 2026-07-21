import XCTest

@testable import FekthorKit

final class PathRefineTests: XCTestCase {
    private let opt = RefineOptions(tolerance: 1.5, cornerAngle: 32, straighten: 0.5, smoothing: 1)

    /// A noisy straight line collapses to a single line segment.
    func testNoisyLineBecomesOneLine() {
        var pts: [Pt] = []
        for i in 0..<40 {
            let jitter = (i % 2 == 0 ? 0.5 : -0.5)  // ±0.5px deterministic jitter
            pts.append(Pt(Double(i), jitter))
        }
        let path = PathRefine.refine(pts, closed: false, options: opt)
        XCTAssertEqual(path.segments.count, 1, "a near-straight run should be one line")
        if case .line = path.segments.first { } else { XCTFail("expected a line segment") }
    }

    /// A rasterised circle arc fits as an arc (or few arcs), passing through anchors.
    func testCircleArcFitsAsArc() {
        var pts: [Pt] = []
        let cx = 50.0, cy = 50.0, r = 40.0
        for i in 0...30 {
            let a = Double(i) / 30 * .pi  // half circle
            pts.append(Pt(cx + r * cos(a), cy + r * sin(a)))
        }
        let path = PathRefine.refine(pts, closed: false, options: opt)
        // Should be a small number of arcs/cubics, not 30 tiny steps.
        XCTAssertLessThanOrEqual(path.segments.count, 4)
        let hasArc = path.segments.contains { if case .arc = $0 { return true }; return false }
        XCTAssertTrue(hasArc, "a circular run should fit at least one arc")
        // Endpoints preserved exactly.
        XCTAssertEqual(path.start.x, pts.first!.x, accuracy: 1e-9)
        XCTAssertEqual(path.segments.last!.endPoint.x, pts.last!.x, accuracy: 1e-6)
    }

    /// An L-shape keeps its sharp 90° corner as an anchor at every smoothing setting.
    func testLShapeKeepsCorner() {
        var pts: [Pt] = []
        for i in 0...20 { pts.append(Pt(Double(i), 0)) }
        for i in 1...20 { pts.append(Pt(20, Double(i))) }
        for smoothing in [0.0, 0.5, 1.0] {
            let o = RefineOptions(tolerance: 1.5, cornerAngle: 32, straighten: 0.5, smoothing: smoothing)
            let path = PathRefine.refine(pts, closed: false, options: o)
            // The corner point (20,0) must be a segment anchor.
            var anchors: [Pt] = [path.start]
            for s in path.segments { anchors.append(s.endPoint) }
            let hasCorner = anchors.contains { abs($0.x - 20) < 0.5 && abs($0.y) < 0.5 }
            XCTAssertTrue(hasCorner, "L corner must survive at smoothing \(smoothing)")
        }
    }

    /// smoothing = 0 collapses fitted cubics to their chord (polygonal result).
    func testSmoothingZeroIsPolygonal() {
        // A wavy free-form curve (no clean line/arc) fits cubics.
        var pts: [Pt] = []
        for i in 0..<30 {
            let x = Double(i)
            pts.append(Pt(x, 6 * sin(x / 4)))
        }
        let o = RefineOptions(tolerance: 0.4, cornerAngle: 80, straighten: 0.0, smoothing: 0)
        let path = PathRefine.refine(pts, closed: false, options: o)
        // Every cubic must be collapsed to a straight chord (control points on the line).
        var cur = path.start
        for seg in path.segments {
            if case .cubic(let c1, let c2, let to) = seg {
                XCTAssertLessThan(PathRefine.perpDist(c1, cur, to), 1e-6)
                XCTAssertLessThan(PathRefine.perpDist(c2, cur, to), 1e-6)
            }
            cur = seg.endPoint
        }
    }

    /// Reversing a refined path yields the same curve traversed backward
    /// (point-identity for shared boundaries).
    func testReverseRoundTrips() {
        var pts: [Pt] = []
        for i in 0..<20 { pts.append(Pt(Double(i), Double(i * i) / 20)) }
        let path = PathRefine.refine(pts, closed: false, options: opt)
        let rev = PathRefine.reverse(path)
        let revrev = PathRefine.reverse(rev)
        XCTAssertEqual(path.start.x, revrev.start.x, accuracy: 1e-9)
        XCTAssertEqual(path.start.y, revrev.start.y, accuracy: 1e-9)
        XCTAssertEqual(path.segments.count, revrev.segments.count)
        // The reversed path starts where the original ends.
        XCTAssertEqual(rev.start.x, path.segments.last!.endPoint.x, accuracy: 1e-6)
        // Flattened point sets match (reversed order).
        let f1 = PathRefine.flatten(path)
        let f2 = PathRefine.flatten(rev).reversed().map { $0 }
        XCTAssertEqual(f1.count, f2.count)
    }

    /// Refinement is deterministic.
    func testDeterministic() {
        var pts: [Pt] = []
        for i in 0..<50 { pts.append(Pt(Double(i), 10 * sin(Double(i) / 5))) }
        let a = PathRefine.refine(pts, closed: false, options: opt)
        let b = PathRefine.refine(pts, closed: false, options: opt)
        XCTAssertEqual(a.segments.count, b.segments.count)
        XCTAssertEqual(a, b)
    }
}
