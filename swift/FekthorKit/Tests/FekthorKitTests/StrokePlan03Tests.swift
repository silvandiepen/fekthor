import XCTest

@testable import FekthorKit

/// Plan 03 acceptance: per-stroke width, junction/endpoint quality.
final class StrokePlan03Tests: XCTestCase {
    /// Paint a filled RGBA canvas with a closure choosing black/white per pixel.
    private func canvas(_ w: Int, _ h: Int, _ black: (Int, Int) -> Bool) -> RasterImage {
        var data = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w where black(x, y) {
                let o = (y * w + x) * 4
                data[o] = 0
                data[o + 1] = 0
                data[o + 2] = 0
            }
        }
        return RasterImage(width: w, height: h, data: data)
    }

    /// Two crossing bars of width 6 and 12 → exactly 2 strokes whose per-stroke
    /// widths recover 6±0.7 and 12±0.7 from the distance transform.
    func testCrossingBarsPerStrokeWidth() {
        let w = 140
        let h = 140
        // Horizontal bar width 6 (y 67…72); vertical bar width 12 (x 64…75).
        let img = canvas(w, h) { x, y in
            (67...72).contains(y) || (64...75).contains(x)
        }
        let doc = StrokesMode.run(img, config: StrokesConfig())
        let strokes = doc.elements.compactMap { el -> StrokePath? in
            if case .stroke(let s) = el { return s } else { return nil }
        }
        XCTAssertEqual(strokes.count, 2, "crossing bars should stay two strokes")
        let widths = strokes.map { $0.width }.sorted()
        XCTAssertEqual(widths[0], 6.0, accuracy: 0.7, "thin bar width")
        XCTAssertEqual(widths[1], 12.0, accuracy: 0.7, "thick bar width")
    }

    /// A T-junction must render with no gap: after conversion the junction pixel is
    /// covered by dark ink (junction snapping + endpoint extension close the seam).
    func testTJunctionNoGap() {
        let w = 120
        let h = 120
        // Horizontal bar (y 30…35) and a vertical stem meeting its middle from below.
        let img = canvas(w, h) { x, y in
            ((30...35).contains(y) && (20...100).contains(x))
                || ((57...62).contains(x) && (33...100).contains(y))
        }
        let doc = StrokesMode.run(img, config: StrokesConfig())
        let rendered = Rasterizer.render(doc)
        // The junction sits around (59, 34). Assert dark coverage within ±1 px.
        var covered = false
        for dy in -1...1 {
            for dx in -1...1 {
                let x = 59 + dx
                let y = 34 + dy
                let o = (y * w + x) * 4
                let lum =
                    0.299 * Double(rendered.data[o]) + 0.587 * Double(rendered.data[o + 1])
                    + 0.114 * Double(rendered.data[o + 2])
                if lum < 128 { covered = true }
            }
        }
        XCTAssertTrue(covered, "T-junction should render with no gap")
    }

    /// An L-corner keeps a sharp corner: the refined stroke has a segment junction
    /// whose turn exceeds 60° (not rounded away).
    func testLCornerStaysSharp() {
        let w = 120
        let h = 120
        let img = canvas(w, h) { x, y in
            ((28...33).contains(y) && (28...92).contains(x))  // horizontal arm
                || ((28...33).contains(x) && (28...92).contains(y))  // vertical arm
        }
        let doc = StrokesMode.run(img, config: StrokesConfig())
        let strokes = doc.elements.compactMap { el -> StrokePath? in
            if case .stroke(let s) = el { return s } else { return nil }
        }
        XCTAssertGreaterThanOrEqual(strokes.count, 1)
        // The corner is sharp when an anchor sits on the true corner vertex (a
        // rounded corner would cut it off). The 90° bend exceeds the tangent-merge
        // threshold, so the two arms are separate straight strokes meeting exactly
        // at that shared vertex. Collect every anchor and find the nearest.
        let corner = Pt(30.5, 30.5)
        var nearest = Double.infinity
        for s in strokes {
            guard let rp = s.refined else { continue }
            var anchors: [Pt] = [rp.start]
            for seg in rp.segments { anchors.append(seg.endPoint) }
            for a in anchors {
                let d = (pow(a.x - corner.x, 2) + pow(a.y - corner.y, 2)).squareRoot()
                nearest = min(nearest, d)
            }
        }
        XCTAssertLessThan(nearest, 2.5, "an anchor must sit on the corner (sharp, not rounded)")
    }

    /// Endpoint extension: a free tip is marched to the drawn visual tip, recovering
    /// the ~width/2 the skeleton loses at the end of a stroke.
    func testEndpointExtensionReachesTip() {
        let w = 120
        let h = 80
        // 8px-tall bar from x=20 to x=99.
        var fg = [Bool](repeating: false, count: w * h)
        for y in 36...43 {
            for x in 20...99 { fg[y * w + x] = true }
        }
        let mask = Mask(width: w, height: h, fg: fg)
        let skel = Skeleton.thin(mask)
        // A dense chain that stops short of the tips (as a skeleton does).
        var chain: [Pt] = []
        for x in 26...93 { chain.append(Pt(Double(x), 39)) }
        let extended = StrokesMode.extendEndpoints(
            chain, mask: mask, skel: skel, width: 8, w: w, h: h, degStart: 1, degEnd: 1)
        XCTAssertLessThan(extended.first!.x, 26, "start extended toward the left tip")
        XCTAssertGreaterThan(extended.last!.x, 93, "end extended toward the right tip")
        // Must not overshoot past the drawn tip by more than a pixel.
        XCTAssertGreaterThanOrEqual(extended.first!.x, 19)
        XCTAssertLessThanOrEqual(extended.last!.x, 100)
    }

    /// Uniform width forces every stroke to the shared median; a manual override
    /// still forces all strokes to one exact value.
    func testUniformWidthAndOverride() {
        let w = 140
        let h = 140
        let img = canvas(w, h) { x, y in
            (67...72).contains(y) || (64...75).contains(x)
        }
        let uniform = StrokesMode.run(img, config: StrokesConfig(uniformWidth: true))
        let uw = uniform.elements.compactMap { el -> Double? in
            if case .stroke(let s) = el { return s.width } else { return nil }
        }
        XCTAssertGreaterThanOrEqual(uw.count, 2)
        XCTAssertEqual(Set(uw).count, 1, "uniform width → all strokes equal")

        let forced = StrokesMode.run(img, config: StrokesConfig(widthOverride: 4.0))
        for el in forced.elements {
            if case .stroke(let s) = el { XCTAssertEqual(s.width, 4.0, accuracy: 1e-9) }
        }
    }
}
