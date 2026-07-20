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

final class ColorTests: XCTestCase {
    /// Two flat colours with a thin anti-aliased seam should auto-detect as two.
    func testQuantizeAutoExcludesAntiAliasing() {
        let w = 64
        let h = 64
        var data = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let o = (y * w + x) * 4
                let red: (UInt8, UInt8, UInt8)
                if x < 31 {
                    red = (220, 30, 30)
                } else if x > 31 {
                    red = (30, 30, 220)
                } else {
                    red = (125, 30, 125)  // 1px AA seam
                }
                data[o] = red.0
                data[o + 1] = red.1
                data[o + 2] = red.2
            }
        }
        let img = RasterImage(width: w, height: h, data: data)
        let q = ColorQuantizer.quantizeAuto(img, maxColors: 8, minFraction: 0.03)
        XCTAssertEqual(q.palette.count, 2, "anti-aliasing seam should be excluded")
    }
}

final class StrokeTests: XCTestCase {
    /// A horizontal and vertical bar crossing should stay ~2 strokes, not
    /// fragment into many at the junction.
    func testStrokesMergeThroughCrossing() {
        let w = 80
        let h = 80
        var data = [UInt8](repeating: 255, count: w * h * 4)
        func paint(_ x: Int, _ y: Int) {
            let o = (y * w + x) * 4
            data[o] = 0
            data[o + 1] = 0
            data[o + 2] = 0
        }
        for y in 0..<h {
            for x in 0..<w {
                if (38...42).contains(x) || (38...42).contains(y) { paint(x, y) }
            }
        }
        let img = RasterImage(width: w, height: h, data: data)
        let doc = StrokesMode.run(img, config: StrokesConfig())
        XCTAssertGreaterThanOrEqual(doc.strokeCount, 1)
        XCTAssertLessThanOrEqual(doc.strokeCount, 4, "crossing should not fragment")
    }
}

final class GradientTests: XCTestCase {
    /// A shaded region should produce at least one gradient-painted fill.
    func testGradientModeProducesGradient() {
        let w = 64
        let h = 64
        var data = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let o = (y * w + x) * 4
                let v = UInt8(30 + (200 * y) / h)  // vertical ramp
                data[o] = v
                data[o + 1] = UInt8(40)
                data[o + 2] = UInt8(200 - Int(v) / 2)
            }
        }
        let img = RasterImage(width: w, height: h, data: data)
        let doc = GradientMode.run(
            img, config: GradientConfig(colors: 8, autoColors: false, simplicity: 0))
        let hasGradient = doc.elements.contains {
            if case .fill(let f) = $0, case .linear = f.paint { return true }
            return false
        }
        XCTAssertTrue(hasGradient, "gradient mode should emit a gradient paint")
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
