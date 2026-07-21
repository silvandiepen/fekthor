import XCTest

@testable import FekthorKit

final class AutoModeTests: XCTestCase {
    private func fixturesDir() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("fixtures/inputs")
    }

    func testFixturesResolveByStageA() throws {
        let cases: [(fixture: String, mode: Mode)] = [
            ("artist-lineart", .strokes),
            ("artist-flat", .shapes),
            ("thor-flat", .shapes),
            ("artist-3d", .gradient),
            ("thor-3d", .gradient),
        ]

        for test in cases {
            let path = fixturesDir().appendingPathComponent("\(test.fixture).png").path
            let img = try RasterImage.load(path: path)
            let detection = AutoMode.detect(img.scaled(maxDimension: 1024))
            XCTAssertEqual(detection.resolved, test.mode, test.fixture)
            XCTAssertEqual(detection.features["stage"], 1, test.fixture)
            XCTAssertGreaterThan(
                detection.confidence, AutoMode.trialConfidenceThreshold, test.fixture)
        }
    }

    func testFlatReferenceRoutesToShapes() throws {
        // AI-generated flat art (rich palette, soft texture) must resolve to
        // shapes, not gradient — guarded by the soft-flat Stage A gate.
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        let path = url.appendingPathComponent("fixtures/references/thor-3d-flattened.png").path
        let img = try RasterImage.load(path: path)
        let detection = AutoMode.detect(img.scaled(maxDimension: 1024))
        XCTAssertEqual(detection.resolved, .shapes)
        XCTAssertEqual(detection.features["stage"], 1)
    }

    func testAmbiguousSyntheticFallsBackToStageB() throws {
        let img = ambiguousSynthetic()
        let detection = AutoMode.detect(img)
        XCTAssertEqual(detection.features["stage"], 2)

        let modes: [Mode] = [.shapes, .strokes, .gradient]
        let scored = try modes.map { mode -> (Mode, Double) in
            let result = try Fekthor.convert(img, mode: mode)
            return (mode, result.quality.overall)
        }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.rawValue < $1.0.rawValue
        }
        XCTAssertEqual(detection.resolved, scored[0].0)
        XCTAssertEqual(detection.resolved, .shapes)
    }

    func testAutoPerformanceBudgets() {
        let lineart = try! RasterImage.load(
            path: fixturesDir().appendingPathComponent("artist-lineart.png").path
        ).scaled(maxDimension: 1024)
        let startA = Date()
        let a = AutoMode.detect(lineart)
        let msA = Date().timeIntervalSince(startA) * 1000
        XCTAssertEqual(a.features["stage"], 1)
        XCTAssertLessThanOrEqual(msA, 80)

        let ambiguous = ambiguousSynthetic()
        let startB = Date()
        let b = AutoMode.detect(ambiguous)
        let msB = Date().timeIntervalSince(startB) * 1000
        XCTAssertEqual(b.features["stage"], 2)
        XCTAssertLessThanOrEqual(msB, 400)
    }

    func testAutoConversionIsDeterministicAndReportsResolvedMode() throws {
        let img = ambiguousSynthetic()
        let a = try Fekthor.convert(img, mode: .auto)
        let b = try Fekthor.convert(img, mode: .auto)
        XCTAssertEqual(a.resolvedMode, .shapes)
        XCTAssertEqual(a.resolvedMode, b.resolvedMode)
        XCTAssertEqual(a.svg, b.svg)
    }

    private func ambiguousSynthetic() -> RasterImage {
        let w = 160
        let h = 120
        var data = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let o = (y * w + x) * 4
                var c: RGB = (244, 244, 244)
                if (12..<70).contains(x) && (16..<82).contains(y) {
                    c = (220, 44, 42)
                }
                let dx = Double(x - 112)
                let dy = Double(y - 60)
                let d = (dx * dx + dy * dy).squareRoot()
                if d < 42 {
                    let t = d / 42
                    c = (
                        UInt8(40 + Int(90 * t)),
                        UInt8(110 + Int(30 * t)),
                        UInt8(210 - Int(80 * t))
                    )
                }
                if (28..<142).contains(x) && (92..<102).contains(y) {
                    c = (42, 138, 82)
                }
                data[o] = c.r
                data[o + 1] = c.g
                data[o + 2] = c.b
                data[o + 3] = 255
            }
        }
        return RasterImage(width: w, height: h, data: data)
    }
}
