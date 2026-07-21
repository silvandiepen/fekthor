import CoreGraphics
import XCTest

@testable import FekthorKit

final class CGPathBuilderTests: XCTestCase {
    /// SVG `A` flags are error-prone (large-arc / sweep). Render a full circle
    /// built from two `RefinedSegment.arc`s through the shared CGPathBuilder and
    /// compare it, pixel for pixel within a small tolerance, against a CG-native
    /// `addEllipse`. If the arc direction or angles were wrong the fills diverge.
    func testArcCircleMatchesNativeEllipse() {
        let w = 120, h = 120
        let c = Pt(60, 60)
        let r = 40.0
        // Two half-circle arcs, both increasing-angle (clockwise in y-down space),
        // forming a full closed circle.
        let right = Pt(c.x + r, c.y)
        let left = Pt(c.x - r, c.y)
        let top = RefinedSegment.arc(
            center: c, radius: r, startAngle: 0, endAngle: .pi, clockwise: true)
        let bottom = RefinedSegment.arc(
            center: c, radius: r, startAngle: .pi, endAngle: 0, clockwise: true)
        _ = left
        let rp = RefinedPath(start: right, segments: [top, bottom], closed: true)
        let doc = VectorDocument(
            width: w, height: h,
            elements: [.fill(FillShape(id: "a", color: (0, 0, 0), geometry: .refined([rp])))])
        let arcImg = Rasterizer.render(doc, smoothing: 1)

        // Reference: the same circle as a native primitive.
        let refDoc = VectorDocument(
            width: w, height: h,
            elements: [.fill(FillShape(id: "b", color: (0, 0, 0), geometry: .circle(center: c, radius: r)))])
        let refImg = Rasterizer.render(refDoc, smoothing: 1)

        var diff = 0
        for i in 0..<(w * h) {
            let o = i * 4
            if abs(Int(arcImg.data[o]) - Int(refImg.data[o])) > 40 { diff += 1 }
        }
        // Allow a few antialiased edge pixels; the fills must otherwise coincide.
        XCTAssertLessThan(diff, 80, "arc-built circle diverged from native circle (\(diff) px)")
    }

    /// A rounded-rect raster is detected as a `rect` primitive with a corner radius.
    func testRoundedRectPrimitive() {
        // Sample a rounded rect boundary densely and detect it.
        let ring = ShapeGeometry.sampleRect(Pt(100, 80), 120, 90, 0, 18)
        // Upsample so detection sees dense points.
        var dense: [Pt] = []
        for i in 0..<ring.count {
            let a = ring[i]
            let b = ring[(i + 1) % ring.count]
            for s in 0..<4 {
                let t = Double(s) / 4
                dense.append(Pt(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t))
            }
        }
        guard let geo = PrimitiveDetect.detect(dense, tolerance: 1.5, straighten: 0.5) else {
            return XCTFail("rounded rect not detected")
        }
        guard case .rect(_, let ww, let hh, _, let cr) = geo else {
            return XCTFail("expected a rect primitive, got \(geo)")
        }
        XCTAssertEqual(ww, 120, accuracy: 3)
        XCTAssertEqual(hh, 90, accuracy: 3)
        XCTAssertGreaterThan(cr, 8, "corner radius should be recovered")
    }

    /// A rasterised circle is detected as a `circle` primitive.
    func testCirclePrimitive() {
        var pts: [Pt] = []
        let c = Pt(50, 50), r = 40.0
        for i in 0..<80 {
            let a = Double(i) / 80 * 2 * .pi
            pts.append(Pt((c.x + r * cos(a)).rounded(), (c.y + r * sin(a)).rounded()))
        }
        guard let geo = PrimitiveDetect.detect(pts, tolerance: 1.5, straighten: 0.5),
            case .circle(let cc, let rr) = geo
        else { return XCTFail("circle not detected") }
        XCTAssertEqual(cc.x, 50, accuracy: 1.5)
        XCTAssertEqual(rr, 40, accuracy: 1.5)
    }
}
