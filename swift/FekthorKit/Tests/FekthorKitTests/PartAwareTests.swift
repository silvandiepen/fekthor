import XCTest

@testable import FekthorKit

/// Part-awareness plumbing tests that do not depend on the Vision model
/// (model output varies by OS): walls and palette partitioning are exercised
/// with synthetic masks.
final class PartAwareTests: XCTestCase {
    /// A background-dominant colour family must not appear inside the subject.
    func testPartitionPaletteReassignsBackgroundFamilies() {
        let w = 8, h = 4
        // Palette: 0 = red (background), 1 = tan (subject).
        let palette: [RGB] = [(200, 30, 30), (220, 190, 150)]
        // Left half background red; right half subject tan except one red pixel.
        var indices = [Int](repeating: 0, count: w * h)
        var walls = [Int](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 4..<w {
                indices[y * w + x] = 1
                walls[y * w + x] = 1
            }
        }
        indices[1 * w + 5] = 0  // red speck inside the subject
        let q = Quantized(width: w, height: h, palette: palette, indices: indices)
        let out = ShapesMode.partitionPalette(q, walls: walls)
        XCTAssertEqual(out.indices[1 * w + 5], 1, "in-subject red must reassign to tan")
        XCTAssertEqual(out.indices[0], 0, "background stays red")
    }

    /// Walls split same-colour components so merging cannot cross a part.
    func testComponentMergeRespectsWalls() {
        let w = 6, h = 2
        let palette: [RGB] = [(10, 10, 10)]
        let indices = [Int](repeating: 0, count: w * h)  // one colour everywhere
        var walls = [Int](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 3..<w { walls[y * w + x] = 1 }
        }
        let (labels, _) = ComponentMerge.merge(
            indices: indices, palette: palette, width: w, height: h,
            minArea: 0, colorThreshold: 1_000_000, walls: walls)
        XCTAssertNotEqual(labels[0], labels[w - 1], "one colour, two parts → two labels")
    }
}
