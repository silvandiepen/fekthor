import CoreGraphics
import XCTest

@testable import FekthorKit

/// Plan 05 — Gradient mode: moment-based merging, radial gradients, background
/// as one shape.
final class GradientPlan05Tests: XCTestCase {

    // MARK: Radial gradient round-trip / renderer agreement

    /// A radial-gradient fill must render as a centre-bright disc via
    /// `CGContext.drawRadialGradient`, and export a `<radialGradient>` def whose
    /// cx/cy/r match the paint. This is the shared-clip contract from plan 02:
    /// export and CoreGraphics preview describe the same geometry.
    func testRadialGradientRenderAndExport() {
        let w = 100, h = 100
        let center = Pt(50, 50)
        let radius = 40.0
        let stops = [
            GradientStop(color: (255, 255, 255), offset: 0),
            GradientStop(color: (0, 0, 0), offset: 1),
        ]
        let paint = Paint.radial(RadialGradient(center: center, radius: radius, stops: stops))
        let ring = ShapeGeometry.samplePrimitiveCircle(center, radius, radius, 0)
        let doc = VectorDocument(
            width: w, height: h,
            elements: [.fill(FillShape(id: "r", paint: paint, geometry: .rings([ring])))])
        let img = Rasterizer.render(doc, background: nil)

        func lum(_ x: Int, _ y: Int) -> Int {
            let o = (y * w + x) * 4
            return Int(img.data[o])
        }
        // Centre reads the inner stop (white); a point near the rim reads dark.
        XCTAssertGreaterThan(lum(50, 50), 200, "radial centre should be bright")
        XCTAssertLessThan(lum(50, 12), 90, "radial rim should be dark")

        let svg = SVGExport.toSVG(doc)
        XCTAssertTrue(svg.contains("<radialGradient"), "missing radialGradient def")
        XCTAssertTrue(svg.contains("cx=\"50\""), "cx mismatch in \(svg)")
        XCTAssertTrue(svg.contains("cy=\"50\""), "cy mismatch")
        XCTAssertTrue(svg.contains("r=\"40\""), "r mismatch")
        XCTAssertTrue(svg.contains("gradientUnits=\"userSpaceOnUse\""), "missing userSpaceOnUse")
    }

    // MARK: Synthetic ramp-rect + radial-disc + flat-ground

    /// Build a crisp scene: a flat-grey ground, a vertical-ramp blue rectangle and
    /// a radially-shaded red disc. The three are colour-distinct, so the moment
    /// merge keeps them as exactly three regions; the disc must fit as a *radial*
    /// gradient (radial beats linear on concentric shading).
    private func makeScene(w: Int, h: Int) -> RasterImage {
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let discC = (170.0, 80.0)
        let discR = 45.0
        for y in 0..<h {
            for x in 0..<w {
                var r = 200.0, g = 205.0, b = 210.0  // ground
                if x >= 20 && x <= 90 && y >= 20 && y <= 140 {
                    let t = Double(y - 20) / 120.0  // vertical ramp
                    r = 30 + 50 * t; g = 60 + 60 * t; b = 180 + 50 * t
                }
                let dx = Double(x) - discC.0, dy = Double(y) - discC.1
                let dist = (dx * dx + dy * dy).squareRoot()
                if dist <= discR {
                    let t = dist / discR  // gentle radial shading (coalesces to one)
                    r = 220 - 45 * t; g = 95 - 35 * t; b = 75 - 25 * t
                }
                let o = (y * w + x) * 4
                data[o] = UInt8(r); data[o + 1] = UInt8(g); data[o + 2] = UInt8(b); data[o + 3] = 255
            }
        }
        return RasterImage(width: w, height: h, data: data)
    }

    func testSyntheticThreeElementsRadialDisc() {
        let img = makeScene(w: 240, h: 160)
        let config = GradientConfig(
            colors: 64, epsilon: 1.5, minArea: 6, stops: 8, autoColors: false, simplicity: 0.6)
        let doc = GradientMode.run(img, config: config)
        XCTAssertEqual(doc.fillCount, 3, "expected ground + rect + disc = 3 fills")

        // The disc region (centred near 170,80) must be a radial gradient.
        var discIsRadial = false
        for el in doc.elements {
            guard case .fill(let f) = el else { continue }
            let rings = f.rings
            var cx = 0.0, cy = 0.0, n = 0.0
            for ring in rings {
                for p in ring { cx += p.x; cy += p.y; n += 1 }
            }
            if n == 0 { continue }
            cx /= n; cy /= n
            if abs(cx - 170) < 25 && abs(cy - 80) < 25 {
                if case .radial = f.paint { discIsRadial = true }
            }
        }
        XCTAssertTrue(discIsRadial, "the radially-shaded disc should fit a radial gradient")
    }

    /// Radial must beat linear (lower RMSE) on a pure concentric disc: fit the disc
    /// alone and confirm `fitRegion` returns radial paint.
    func testRadialBeatsLinearOnDisc() {
        let w = 120, h = 120
        var data = [UInt8](repeating: 0, count: w * h * 4)
        var labels = [Int](repeating: 1, count: w * h)  // 1 = outside
        let c = (60.0, 60.0), radius = 45.0
        for y in 0..<h {
            for x in 0..<w {
                let dx = Double(x) - c.0, dy = Double(y) - c.1
                let dist = (dx * dx + dy * dy).squareRoot()
                let o = (y * w + x) * 4
                if dist <= radius {
                    let t = dist / radius
                    data[o] = UInt8(240 - 120 * t)
                    data[o + 1] = UInt8(210 - 100 * t)
                    data[o + 2] = UInt8(200 - 90 * t)
                    data[o + 3] = 255
                    labels[y * w + x] = 0  // 0 = disc
                }
            }
        }
        let img = RasterImage(width: w, height: h, data: data)
        let paint = GradientFit.fitRegion(
            img: img, labels: labels, label: 0, bbox: (14, 14, 106, 106),
            fallback: (180, 150, 140), stops: 8)
        guard case .radial = paint else {
            return XCTFail("concentric disc should fit radial, got \(paint)")
        }
    }

    // MARK: Background as a single shape

    /// On both 3D fixtures, ≥55% of the image-border pixels must belong to one
    /// region (the background is one shape, not a fragmented vignette). Uses the
    /// real segmentation parameters via `GradientMode.segment`.
    func testBackgroundSingleRegion() throws {
        for name in ["thor-3d", "artist-3d"] {
            let path = fixtureURL(name).path
            let full = try RasterImage.load(path: path)
            let img = full.scaled(maxDimension: 512)
            let config = GradientConfig(
                colors: 64, epsilon: 1.5, minArea: 6, stops: 8, autoColors: false, simplicity: 0.3)
            let (labels, _) = GradientMode.segment(img, config: config)
            let w = img.width, h = img.height
            var counts: [Int: Int] = [:]
            var total = 0
            for x in 0..<w {
                counts[labels[x], default: 0] += 1
                counts[labels[(h - 1) * w + x], default: 0] += 1
                total += 2
            }
            for y in 0..<h {
                counts[labels[y * w], default: 0] += 1
                counts[labels[y * w + w - 1], default: 0] += 1
                total += 2
            }
            let maxShare = Double(counts.values.max() ?? 0) / Double(total)
            XCTAssertGreaterThanOrEqual(
                maxShare, 0.55, "\(name): largest border region only \(maxShare) of border")
        }
    }

    // MARK: Blend monotonicity

    /// Sweeping Blend 0→100% must strictly decrease the fill count (no gaps): more
    /// merging → fewer shapes.
    func testBlendMonotonicity() throws {
        let full = try RasterImage.load(path: fixtureURL("thor-3d").path)
        let img = full.scaled(maxDimension: 512)
        var counts: [Int] = []
        for s in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let config = GradientConfig(
                colors: 64, epsilon: 1.5, minArea: 6, stops: 8, autoColors: false, simplicity: s)
            counts.append(GradientMode.run(img, config: config).fillCount)
        }
        for i in 1..<counts.count {
            XCTAssertLessThan(
                counts[i], counts[i - 1], "fill count not strictly decreasing: \(counts)")
        }
    }

    // MARK: Determinism

    /// Two conversions of the same input produce byte-identical SVG (PQ ties and
    /// region ordering are deterministic).
    func testGradientDeterminism() throws {
        let full = try RasterImage.load(path: fixtureURL("artist-3d").path)
        let img = full.scaled(maxDimension: 384)
        let a = try Fekthor.convert(img, mode: .gradient).svg
        let b = try Fekthor.convert(img, mode: .gradient).svg
        XCTAssertEqual(a, b, "gradient SVG must be byte-identical across runs")
    }

    private func fixtureURL(_ name: String) -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("fixtures/inputs/\(name).png")
    }
}
