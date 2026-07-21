import XCTest

@testable import FekthorKit

final class AutoTuneTests: XCTestCase {
    private func fixture(_ name: String) throws -> RasterImage {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return try RasterImage.load(
            path: url.appendingPathComponent("fixtures/inputs/\(name).png").path)
    }

    func testSearchImprovesOrMatchesDefaultsAndIsDeterministic() throws {
        let img = try fixture("artist-flat")
        let base = Fekthor.Options()
        let a = AutoTune.search(img, mode: .shapes, base: base)
        XCTAssertGreaterThan(a.score, 0)
        XCTAssertEqual(a.resolvedMode, .shapes)

        // The winner must not score below the defaults on the same thumbnail.
        let thumb = img.scaled(maxDimension: AutoTune.thumbnailMaxDimension)
        let defaults = try Fekthor.convert(thumb, mode: .shapes, options: base)
        XCTAssertGreaterThanOrEqual(a.score + 1e-9, defaults.quality.overall)

        let b = AutoTune.search(img, mode: .shapes, base: base)
        XCTAssertEqual(a.score, b.score)
        XCTAssertEqual(a.options.epsilon, b.options.epsilon)
        XCTAssertEqual(a.options.simplicity, b.options.simplicity)
        XCTAssertEqual(a.options.smoothing, b.options.smoothing)
    }
}
