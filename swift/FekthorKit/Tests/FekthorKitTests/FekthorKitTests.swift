import XCTest

@testable import FekthorKit

final class GeometryTests: XCTestCase {
    func testAreaOfUnitSquare() {
        let sq = [Pt(0, 0), Pt(0, 1), Pt(1, 1), Pt(1, 0)]
        XCTAssertEqual(Geometry.area(sq), 1.0, accuracy: 1e-9)
    }

    func testSimplifyOpenDropsCollinear() {
        let line = [Pt(0, 0), Pt(1, 0), Pt(2, 0), Pt(3, 0)]
        let s = Geometry.simplifyOpen(line, epsilon: 0.1)
        XCTAssertEqual(s.count, 2)
    }

    func testSimplifyClosedPreservesCorners() {
        // A square sampled densely should simplify to ~4 corners.
        var ring: [Pt] = []
        for i in 0..<10 { ring.append(Pt(Double(i), 0)) }
        for i in 0..<10 { ring.append(Pt(9, Double(i))) }
        for i in 0..<10 { ring.append(Pt(Double(9 - i), 9)) }
        for i in 0..<10 { ring.append(Pt(0, Double(9 - i))) }
        let s = Geometry.simplifyClosed(ring, epsilon: 0.5)
        XCTAssertLessThanOrEqual(s.count, 6)
        XCTAssertGreaterThanOrEqual(s.count, 4)
    }
}

final class QuantizerTests: XCTestCase {
    /// Two solid colour blocks quantize deterministically to two palette entries.
    func testTwoColourImageIsDeterministic() {
        let w = 32
        let h = 32
        var data = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let o = (y * w + x) * 4
                let left = x < w / 2
                data[o] = left ? 200 : 20
                data[o + 1] = left ? 30 : 180
                data[o + 2] = 40
                data[o + 3] = 255
            }
        }
        let img = RasterImage(width: w, height: h, data: data)
        let a = ColorQuantizer.quantize(img, k: 2, iters: 6)
        let b = ColorQuantizer.quantize(img, k: 2, iters: 6)
        XCTAssertEqual(a.indices, b.indices, "quantization must be deterministic")
        XCTAssertEqual(a.palette.count, 2)
    }
}

final class RoundTripTests: XCTestCase {
    /// A quantized synthetic image should reconstruct to high fidelity.
    func testShapesRoundTripFidelity() throws {
        let w = 64
        let h = 64
        var data = [UInt8](repeating: 255, count: w * h * 4)
        // Blue background, red square in the middle.
        for y in 0..<h {
            for x in 0..<w {
                let o = (y * w + x) * 4
                let inSquare = (16..<48).contains(x) && (16..<48).contains(y)
                data[o] = inSquare ? 220 : 40
                data[o + 1] = inSquare ? 30 : 90
                data[o + 2] = inSquare ? 30 : 200
                data[o + 3] = 255
            }
        }
        let img = RasterImage(width: w, height: h, data: data)
        let result = try Fekthor.convert(img, mode: .shapes)
        // Curve smoothing rounds the square's corners slightly, so allow ~85%.
        XCTAssertGreaterThan(result.metrics.exactPct, 85.0)
        XCTAssertGreaterThanOrEqual(result.document.fillCount, 2)
    }
}
