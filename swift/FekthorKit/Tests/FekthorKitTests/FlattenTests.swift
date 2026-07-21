import XCTest

@testable import FekthorKit

/// Plan 07 — Flatten (hue-aware colour reduction) acceptance.
final class FlattenTests: XCTestCase {
    private func fixturesDir() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("fixtures/inputs")
    }

    private func fillColors(_ doc: VectorDocument) -> [RGB] {
        doc.elements.compactMap {
            if case .fill(let f) = $0, case .solid(let c) = f.paint, c.count >= 3 {
                return (c[0], c[1], c[2])
            }
            return nil
        }
    }

    // MARK: - Palette family clustering (unit)

    /// Complete-linkage clustering collapses two shades of one hue and keeps the
    /// dominant member as the representative (mode, not mean); a distinct hue stays.
    func testFamilyReduceDominantAndDistinct() {
        // 3 fine entries: light blond (small), dark blond (large), steel-blue.
        let palette: [RGB] = [(236, 208, 164), (150, 116, 66), (90, 120, 204)]
        var indices: [Int] = []
        indices += Array(repeating: 0, count: 100)  // light blond, minority
        indices += Array(repeating: 1, count: 400)  // dark blond, dominant
        indices += Array(repeating: 2, count: 250)  // steel-blue
        let q = Quantized(width: 750, height: 1, palette: palette, indices: indices)
        let reduced = PaletteFamily.reduce(q, targetColors: 2, flatten: 0.7, separation: 0.10)
        XCTAssertEqual(reduced.palette.count, 2, "two families remain")
        // The blond family's colour is the dominant (dark blond), never a blend.
        XCTAssertTrue(
            reduced.palette.contains { $0 == (150, 116, 66) }, "dominant blond is the representative")
        XCTAssertTrue(reduced.palette.contains { $0 == (90, 120, 204) }, "steel-blue stays distinct")
    }

    // MARK: - Synthetic shaded sphere

    /// A disc shaded in 6 blues on a 3-green background, Shapes/Colours=2/Flatten=70%
    /// must resolve to exactly 2 fills (one blue, one green) with the disc silhouette
    /// preserved (IoU vs the true disc ≥ 0.97).
    func testShadedSphereCollapsesToTwoFills() throws {
        let w = 256, h = 256
        let cx = 128.0, cy = 128.0, radius = 92.0
        let blues: [RGB] = [
            (24, 36, 110), (40, 58, 140), (58, 84, 168), (80, 112, 196), (108, 144, 220),
            (140, 176, 240),
        ]
        let greens: [RGB] = [(30, 96, 44), (52, 132, 66), (78, 164, 96)]
        var data = [UInt8](repeating: 0, count: w * h * 4)
        var trueDisc = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let dr = ((Double(x) - cx) * (Double(x) - cx) + (Double(y) - cy) * (Double(y) - cy))
                    .squareRoot()
                let c: RGB
                if dr <= radius {
                    trueDisc[y * w + x] = true
                    c = blues[min(5, Int(dr / (radius / 6.0)))]
                } else {
                    c = greens[x < 85 ? 0 : (x < 171 ? 1 : 2)]
                }
                let o = (y * w + x) * 4
                data[o] = c.r
                data[o + 1] = c.g
                data[o + 2] = c.b
                data[o + 3] = 255
            }
        }
        let img = RasterImage(width: w, height: h, data: data)
        let result = try Fekthor.convert(
            img, mode: .shapes, options: Fekthor.Options(colors: 2, flatten: 0.7))
        let colors = fillColors(result.document)
        XCTAssertEqual(colors.count, 2, "exactly two flat fills: one blue, one green")

        // Identify the blue family colour and rebuild its silhouette from the render.
        guard let blue = colors.max(by: { Int($0.b) - Int($0.r) < Int($1.b) - Int($1.r) }) else {
            return XCTFail("no blue fill")
        }
        let rendered = result.rendered
        var inter = 0, union = 0
        for i in 0..<(w * h) {
            let o = i * 4
            let px: RGB = (rendered.data[o], rendered.data[o + 1], rendered.data[o + 2])
            let isBlue =
                ColorQuantizer.dist2(px, blue)
                < ColorQuantizer.dist2(px, colors[0] == blue ? colors[1] : colors[0])
            if isBlue && trueDisc[i] { inter += 1 }
            if isBlue || trueDisc[i] { union += 1 }
        }
        let iou = Double(inter) / Double(union)
        XCTAssertGreaterThanOrEqual(iou, 0.97, "sphere silhouette preserved, IoU \(iou)")
    }

    // MARK: - thor-3d headline demo

    /// thor-3d, Shapes, Colours≈12, Flatten≈70%: ≤45 flat fills, cape red a separate
    /// fill from background red, eyes still black.
    func testThorFlattenHeadline() throws {
        let path = fixturesDir().appendingPathComponent("thor-3d.png").path
        let full = try RasterImage.load(path: path)
        let working = full.scaled(maxDimension: 1024)
        let result = try Fekthor.convert(
            working, mode: .shapes, options: Fekthor.Options(colors: 12, flatten: 0.7))
        let colors = fillColors(result.document)
        XCTAssertLessThanOrEqual(colors.count, 45, "total fills ≤ 45, got \(colors.count)")

        // Two distinct reds: a bright background red and a darker cape red.
        let reds = colors.filter { $0.r > 140 && $0.g < 100 && $0.b < 100 }
        let distinctReds = Set(reds.map { Int($0.r) << 16 | Int($0.g) << 8 | Int($0.b) })
        XCTAssertGreaterThanOrEqual(
            distinctReds.count, 2, "cape red stays a separate fill from background red")

        // Eyes stay black: a near-neutral very dark fill survives.
        XCTAssertTrue(
            colors.contains { $0.r < 45 && $0.g < 45 && $0.b < 45 }, "eyes stay black")
    }

    // MARK: - Regression guarantees

    /// Flatten = 0 is byte-identical to the default (non-flatten) pipeline on every
    /// fixture — the slider only *adds* pressure above zero.
    func testFlattenZeroByteIdentical() throws {
        let fm = FileManager.default
        let dir = fixturesDir()
        for entry in (try? fm.contentsOfDirectory(atPath: dir.path))?.sorted() ?? []
        where entry.hasSuffix(".png") {
            let full = try RasterImage.load(path: dir.appendingPathComponent(entry).path)
            let working = full.scaled(maxDimension: 1024)
            let base = try Fekthor.convert(working, mode: .shapes).svg
            let flat0 = try Fekthor.convert(
                working, mode: .shapes, options: Fekthor.Options(flatten: 0)).svg
            XCTAssertEqual(base, flat0, "\(entry): flatten=0 SVG must equal the default SVG")
        }
    }

    /// Already-flat art is visually unchanged at Flatten ≤ 30% (no shade families to
    /// collapse): the render still matches the source closely and fills don't explode.
    func testArtistFlatUnchangedUnderFlatten() throws {
        let path = fixturesDir().appendingPathComponent("artist-flat.png").path
        let working = try RasterImage.load(path: path).scaled(maxDimension: 1024)
        for flatten in [0.1, 0.3] {
            let r = try Fekthor.convert(
                working, mode: .shapes, options: Fekthor.Options(colors: 16, flatten: flatten))
            XCTAssertGreaterThanOrEqual(
                r.metrics.psnr, 30.0, "artist-flat at \(flatten) stays visually faithful (PSNR)")
            XCTAssertGreaterThanOrEqual(
                r.metrics.exactPct, 90.0, "artist-flat at \(flatten) exact-match holds")
            XCTAssertLessThanOrEqual(
                r.document.fillCount, 30, "artist-flat at \(flatten) does not fragment")
        }
    }

    /// Determinism across two conversions at a non-zero Flatten (invariant #1).
    func testFlattenDeterministic() throws {
        let path = fixturesDir().appendingPathComponent("thor-3d.png").path
        let working = try RasterImage.load(path: path).scaled(maxDimension: 1024)
        let a = try Fekthor.convert(
            working, mode: .shapes, options: Fekthor.Options(colors: 12, flatten: 0.7)).svg
        let b = try Fekthor.convert(
            working, mode: .shapes, options: Fekthor.Options(colors: 12, flatten: 0.7)).svg
        XCTAssertEqual(a, b, "flatten output is byte-identical across runs")
    }
}
