import CoreGraphics
import XCTest

@testable import FekthorKit

/// Plan 05 — Gradient mode: moment-based merging, radial gradients, background
/// as one shape.
final class GradientPlan05Tests: XCTestCase {

    // MARK: Radial gradient round-trip / renderer agreement

    /// A radial-gradient fill must render as a centre-bright disc via
    /// `CGContext.drawRadialGradient`, and export a `<radialGradient>` def whose
    /// cx/cy/r match the paint. This is the shared-clip contract from plan 02:
    /// export and CoreGraphics preview describe the same geometry.
    func testRadialGradientRenderAndExport() {
        let w = 100, h = 100
        let center = Pt(50, 50)
        let radius = 40.0
        let stops = [
            GradientStop(color: (255, 255, 255), offset: 0),
            GradientStop(color: (0, 0, 0), offset: 1),
        ]
        let paint = Paint.radial(RadialGradient(center: center, radius: radius, stops: stops))
        let ring = ShapeGeometry.samplePrimitiveCircle(center, radius, radius, 0)
        let doc = VectorDocument(
            width: w, height: h,
            elements: [.fill(FillShape(id: "r", paint: paint, geometry: .rings([ring])))])
        let img = Rasterizer.render(doc, background: nil)

        func lum(_ x: Int, _ y: Int) -> Int {
            let o = (y * w + x) * 4
            return Int(img.data[o])
        }
        // Centre reads the inner stop (white); a point near the rim reads dark.
        XCTAssertGreaterThan(lum(50, 50), 200, "radial centre should be bright")
        XCTAssertLessThan(lum(50, 12), 90, "radial rim should be dark")

        let svg = SVGExport.toSVG(doc)
        XCTAssertTrue(svg.contains("<radialGradient"), "missing radialGradient def")
        XCTAssertTrue(svg.contains("cx=\"50\""), "cx mismatch in \(svg)")
        XCTAssertTrue(svg.contains("cy=\"50\""), "cy mismatch")
        XCTAssertTrue(svg.contains("r=\"40\""), "r mismatch")
        XCTAssertTrue(svg.contains("gradientUnits=\"userSpaceOnUse\""), "missing userSpaceOnUse")
    }
}
