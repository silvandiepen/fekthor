import XCTest

@testable import FekthorKit

final class TaperTests: XCTestCase {
    /// A bar that is constant-width on the left and narrows to a point on the
    /// right: with taper off it stays one stroke; with taper on the narrowing tail
    /// becomes an outline fill while the body remains a real stroke.
    private func taperingBar() -> RasterImage {
        let w = 160
        let h = 80
        var data = [UInt8](repeating: 255, count: w * h * 4)
        let cy = 40
        for x in 20..<140 {
            // Half-height: 5px for the body, linearly to 0 over the last 40px.
            let half: Int
            if x < 100 {
                half = 5
            } else {
                half = Int((5.0 * Double(140 - x) / 40.0).rounded())
            }
            for dy in -half...half {
                let y = cy + dy
                if y >= 0 && y < h {
                    let o = (y * w + x) * 4
                    data[o] = 0
                    data[o + 1] = 0
                    data[o + 2] = 0
                }
            }
        }
        return RasterImage(width: w, height: h, data: data)
    }

    func testTaperOffStaysStroke() {
        let doc = StrokesMode.run(taperingBar(), config: StrokesConfig(taper: false))
        let fills = doc.elements.filter { if case .fill = $0 { return true } else { return false } }
        XCTAssertTrue(fills.isEmpty, "taper off should emit no outline fills")
        XCTAssertGreaterThanOrEqual(doc.strokeCount, 1)
    }

    func testTaperOnEmitsTailFill() {
        let doc = StrokesMode.run(taperingBar(), config: StrokesConfig(taper: true))
        let fills = doc.elements.filter { if case .fill = $0 { return true } else { return false } }
        XCTAssertGreaterThanOrEqual(fills.count, 1, "taper on should emit a tail outline fill")
        XCTAssertGreaterThanOrEqual(doc.strokeCount, 1, "the body must remain a real stroke")
    }
}
