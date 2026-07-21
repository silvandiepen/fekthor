import XCTest

@testable import FekthorKit

/// Per-fixture, per-canonical-mode minimum overall quality. Floors sit ~0.03
/// below the measured baseline at implementation time so noise does not flake
/// but a real regression fails. Raise these as later plans improve results.
final class EvalRegressionTests: XCTestCase {
    /// Canonical mode per fixture family, and the minimum acceptable overall.
    private let floors: [(fixture: String, mode: Mode, floor: Double)] = [
        ("artist-lineart", .strokes, 0.80),  // baseline 0.832
        ("artist-flat", .shapes, 0.65),  // baseline 0.679
        ("thor-flat", .shapes, 0.36),  // baseline 0.396
        ("artist-3d", .gradient, 0.45),  // baseline 0.481
        ("thor-3d", .gradient, 0.19),  // baseline 0.219
    ]

    /// Repo-root `fixtures/inputs`, resolved from this source file's location.
    private func fixturesDir() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }  // …/Tests/FekthorKitTests/<file>
        return url.appendingPathComponent("fixtures/inputs")
    }

    func testCanonicalModesMeetFloors() throws {
        let dir = fixturesDir()
        for (fixture, mode, floor) in floors {
            let path = dir.appendingPathComponent("\(fixture).png").path
            guard let full = try? RasterImage.load(path: path) else {
                XCTFail("missing fixture: \(path)")
                continue
            }
            // Same working size as the app / eval harness.
            let working = full.scaled(maxDimension: 1024)
            let result = try Fekthor.convert(working, mode: mode)
            XCTAssertGreaterThanOrEqual(
                result.quality.overall, floor,
                "\(fixture)/\(mode.rawValue) overall \(result.quality.overall) below floor \(floor)")
        }
    }

    /// The metric must rank modes per family: Gradient beats Strokes on shaded 3D
    /// art (sanity that Auto mode, plan 06, can trust these scores to pick a mode).
    func testGradientBeatsStrokesOnShaded() throws {
        let path = fixturesDir().appendingPathComponent("artist-3d.png").path
        let full = try RasterImage.load(path: path)
        let working = full.scaled(maxDimension: 1024)
        let grad = try Fekthor.convert(working, mode: .gradient).quality.overall
        let strokes = try Fekthor.convert(working, mode: .strokes).quality.overall
        XCTAssertGreaterThan(grad, strokes, "gradient should beat strokes on shaded art")
    }
}
