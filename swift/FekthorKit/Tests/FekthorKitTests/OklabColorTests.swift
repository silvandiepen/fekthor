import XCTest

@testable import FekthorKit

/// Plan 07 — Oklab colour space + the single flatten metric.
final class OklabColorTests: XCTestCase {
    /// sRGB → Oklab against published reference values (Björn Ottosson), ±0.002.
    func testReferenceValues() {
        let cases: [(rgb: RGB, L: Double, a: Double, b: Double)] = [
            ((255, 255, 255), 1.00000, 0.00000, 0.00000),
            ((0, 0, 0), 0.00000, 0.00000, 0.00000),
            ((255, 0, 0), 0.62796, 0.22486, 0.12585),
            ((0, 255, 0), 0.86644, -0.23389, 0.17950),
            ((0, 0, 255), 0.45201, -0.03246, -0.31153),
            ((128, 128, 128), 0.59987, 0.00000, 0.00000),
        ]
        for c in cases {
            let lab = OklabColor.from(c.rgb)
            XCTAssertEqual(lab.L, c.L, accuracy: 0.002, "L for \(c.rgb)")
            XCTAssertEqual(lab.a, c.a, accuracy: 0.002, "a for \(c.rgb)")
            XCTAssertEqual(lab.b, c.b, accuracy: 0.002, "b for \(c.rgb)")
        }
    }

    /// Neutral greys have a ≈ b ≈ 0 — hue-less, so they separate from colours by
    /// chroma alone (no neutral special-casing needed in the flatten metric).
    func testNeutralsAreHueless() {
        for v: UInt8 in [0, 40, 128, 200, 255] {
            let lab = OklabColor.from((v, v, v))
            XCTAssertEqual(lab.a, 0, accuracy: 0.001)
            XCTAssertEqual(lab.b, 0, accuracy: 0.001)
        }
    }

    /// The headline ranking inversion: two shades of one hue (light/dark blond)
    /// are *farther* apart than blond↔steel-blue in Euclidean RGB, yet the flatten
    /// metric at flatten ≥ 0.5 ranks the blonds *closer* — shades collapse, hues stay.
    func testFlattenRankingInversion() {
        let lightBlond: RGB = (236, 208, 164)
        let darkBlond: RGB = (126, 96, 50)
        let blond: RGB = (181, 152, 107)
        let steelBlue: RGB = (90, 120, 204)

        func rgb2(_ a: RGB, _ b: RGB) -> Int {
            let dr = Int(a.r) - Int(b.r), dg = Int(a.g) - Int(b.g), db = Int(a.b) - Int(b.b)
            return dr * dr + dg * dg + db * db
        }
        // RGB ranks the blonds farther apart than blond↔steel-blue.
        XCTAssertGreaterThan(rgb2(lightBlond, darkBlond), rgb2(blond, steelBlue))

        let lbLab = OklabColor.from(lightBlond)
        let dbLab = OklabColor.from(darkBlond)
        let blLab = OklabColor.from(blond)
        let stLab = OklabColor.from(steelBlue)
        for flatten in [0.5, 0.7, 1.0] {
            let shade = OklabColor.flattenDistance(lbLab, dbLab, flatten: flatten)
            let hue = OklabColor.flattenDistance(blLab, stLab, flatten: flatten)
            XCTAssertLessThan(
                shade, hue, "at flatten \(flatten) the two blonds must rank closer than blond↔blue")
        }
    }

    /// flatten = 0 is a plain perceptual distance (weights collapse to 1, 1).
    func testFlattenZeroWeights() {
        let a = OklabColor.from((10, 20, 30))
        let b = OklabColor.from((200, 60, 90))
        let plain =
            (a.L - b.L) * (a.L - b.L) + (a.a - b.a) * (a.a - b.a) + (a.b - b.b) * (a.b - b.b)
        XCTAssertEqual(OklabColor.flattenDistance(a, b, flatten: 0), plain, accuracy: 1e-9)
    }
}
