import XCTest

@testable import FekthorKit

final class ChamferTests: XCTestCase {
    private func mask(_ w: Int, _ h: Int, _ on: [(Int, Int)]) -> [Bool] {
        var m = [Bool](repeating: false, count: w * h)
        for (x, y) in on { m[y * w + x] = true }
        return m
    }

    /// The 3-4 distance transform on a single feature at the origin: orthogonal
    /// neighbours are 1px, the (1,1) diagonal is 4/3px, three steps out is 3px.
    func testDistanceTransformKnown() {
        let w = 6, h = 6
        let dt = Quality.distanceTransform(mask(w, h, [(0, 0)]), width: w, height: h)
        XCTAssertEqual(dt[0], 0, accuracy: 1e-9)
        XCTAssertEqual(dt[0 * w + 1], 1.0, accuracy: 1e-9)  // (1,0)
        XCTAssertEqual(dt[1 * w + 0], 1.0, accuracy: 1e-9)  // (0,1)
        XCTAssertEqual(dt[1 * w + 1], 4.0 / 3.0, accuracy: 1e-9)  // (1,1) diagonal
        XCTAssertEqual(dt[0 * w + 3], 3.0, accuracy: 1e-9)  // (3,0) three ortho steps
    }

    /// Identical masks are perfectly aligned → zero distance.
    func testChamferIdenticalMasksZero() {
        let w = 8, h = 8
        let m = mask(w, h, [(2, 2), (3, 4), (5, 1)])
        XCTAssertEqual(Quality.symmetricChamfer(m, m, width: w, height: h), 0, accuracy: 1e-9)
    }

    /// Two single pixels three columns apart: the symmetric mean chamfer is
    /// exactly the orthogonal distance, 3px.
    func testChamferKnownOrthogonalDistance() {
        let w = 8, h = 8
        let a = mask(w, h, [(0, 0)])
        let b = mask(w, h, [(3, 0)])
        XCTAssertEqual(Quality.symmetricChamfer(a, b, width: w, height: h), 3.0, accuracy: 1e-9)
    }

    /// One empty mask is a total mismatch → a large, finite saturating distance.
    func testChamferEmptyVsNonEmptySaturates() {
        let w = 8, h = 8
        let a = mask(w, h, [(4, 4)])
        let empty = [Bool](repeating: false, count: w * h)
        let d = Quality.symmetricChamfer(a, empty, width: w, height: h)
        XCTAssertGreaterThanOrEqual(d, Double(w))
        XCTAssertTrue(d.isFinite)
    }
}

final class QualityMonotonicityTests: XCTestCase {
    /// A black square on white; a perfect copy scores full fidelity, and adding
    /// noise to the rendered image must lower it (both the pixel and edge terms).
    func testAddingNoiseLowersShapesFidelity() {
        let w = 64, h = 64
        var data = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let o = (y * w + x) * 4
                let inSquare = (16..<48).contains(x) && (16..<48).contains(y)
                let v: UInt8 = inSquare ? 0 : 255
                data[o] = v
                data[o + 1] = v
                data[o + 2] = v
                data[o + 3] = 255
            }
        }
        let source = RasterImage(width: w, height: h, data: data)
        let clean = RasterImage(width: w, height: h, data: data)

        var noisy = data
        // Deterministic salt-and-pepper: flip ~20% of pixels to the opposite tone.
        for i in 0..<(w * h) where (i * 2_654_435_761) % 5 == 0 {
            let o = i * 4
            let flipped: UInt8 = noisy[o] > 127 ? 0 : 255
            noisy[o] = flipped
            noisy[o + 1] = flipped
            noisy[o + 2] = flipped
        }
        let noisyImg = RasterImage(width: w, height: h, data: noisy)

        var d1: [String: Double] = [:]
        var d2: [String: Double] = [:]
        let clean_f = Quality.shapesFidelity(source, clean, &d1)
        let noisy_f = Quality.shapesFidelity(source, noisyImg, &d2)
        XCTAssertEqual(clean_f, 1.0, accuracy: 1e-6, "a perfect copy is full fidelity")
        XCTAssertLessThan(noisy_f, clean_f, "noise must lower fidelity")
    }

    /// Fewer nodes / paths score higher simplicity.
    func testSimplicityDecreasesWithNodes() {
        func doc(nodes: Int) -> VectorDocument {
            var ring: [Pt] = []
            for i in 0..<nodes { ring.append(Pt(Double(i), 0)) }
            return VectorDocument(
                width: 100, height: 100,
                elements: [.fill(FillShape(id: "f", color: (0, 0, 0), rings: [ring]))])
        }
        var d: [String: Double] = [:]
        let small = Quality.simplicityScore(doc(nodes: 20), &d)
        let large = Quality.simplicityScore(doc(nodes: 5000), &d)
        XCTAssertGreaterThan(small, large)
    }
}

final class QualityDeterminismTests: XCTestCase {
    /// Two conversions of the same input yield identical SVG and quality — the
    /// report the eval harness serialises is byte-stable (within a process; the
    /// cross-process gate is the sorted region ordering in ComponentMerge/PlanarMap).
    func testConvertIsDeterministic() throws {
        let w = 96, h = 96
        var data = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let o = (y * w + x) * 4
                data[o] = UInt8((x * 255) / w)
                data[o + 1] = UInt8((y * 255) / h)
                data[o + 2] = 128
            }
        }
        let img = RasterImage(width: w, height: h, data: data)
        let a = try Fekthor.convert(img, mode: .shapes)
        let b = try Fekthor.convert(img, mode: .shapes)
        XCTAssertEqual(a.svg, b.svg)
        XCTAssertEqual(a.quality.overall, b.quality.overall)
        XCTAssertEqual(a.quality.detail, b.quality.detail)
    }
}
