import XCTest

@testable import FekthorKit

final class DistanceTransformTests: XCTestCase {
    /// A single seed at the centre: every pixel's distance is the exact Euclidean
    /// distance to that seed (the transform must be exact, not a 3-4 chamfer).
    func testExactEuclideanFromSingleSeed() {
        let w = 9
        let h = 9
        var seeds = [Bool](repeating: false, count: w * h)
        seeds[4 * w + 4] = true
        let d = DistanceTransform.distance(fromSeeds: seeds, width: w, height: h)
        for y in 0..<h {
            for x in 0..<w {
                let expected = (Double((x - 4) * (x - 4) + (y - 4) * (y - 4))).squareRoot()
                XCTAssertEqual(d[y * w + x], expected, accuracy: 1e-9)
            }
        }
    }

    /// A solid vertical bar of width 6: the centre columns of a foreground bar are
    /// ~3px from background, so 2×dt ≈ 6 (the bar width).
    func testBarWidthViaDoubleDt() {
        let w = 40
        let h = 40
        var fg = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 17..<23 {  // 6px-wide bar (x = 17…22)
                fg[y * w + x] = true
            }
        }
        let mask = Mask(width: w, height: h, fg: fg)
        let dt = DistanceTransform.toBackground(mask)
        // The two centremost columns (x=19,20) are 3px from the nearest edge.
        let centreWidth = 2 * dt[20 * w + 19]
        XCTAssertEqual(centreWidth, 6.0, accuracy: 0.7)
    }

    /// Background pixels have distance 0; the transform is symmetric.
    func testSeedsAreZero() {
        let w = 5
        let h = 5
        var seeds = [Bool](repeating: false, count: w * h)
        seeds[0] = true
        seeds[24] = true
        let d = DistanceTransform.distance(fromSeeds: seeds, width: w, height: h)
        XCTAssertEqual(d[0], 0, accuracy: 1e-12)
        XCTAssertEqual(d[24], 0, accuracy: 1e-12)
    }
}
