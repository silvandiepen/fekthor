import XCTest

@testable import FekthorKit

final class Model2BridgeTests: XCTestCase {
    func testStrokeMapsLosslessly() {
        let refined = RefinedPath(
            start: Pt(2, 2), segments: [.line(to: Pt(20, 2))], closed: false)
        let doc = VectorDocument(
            width: 24, height: 24,
            elements: [
                .stroke(
                    StrokePath(
                        id: "s0", color: (1, 1, 1), width: 1.5, closed: false,
                        points: [Pt(2, 2), Pt(20, 2)], cap: .round, refined: refined))
            ])
        let out = Model2Bridge.document(from: doc)
        XCTAssertEqual(out.viewBox?.width, 24)
        XCTAssertEqual(out.nodes.count, 1)
        guard case .shape(let shape) = out.nodes[0] else { return XCTFail() }
        guard case .path(let paths) = shape.kind else { return XCTFail() }
        // The refined geometry passes through untouched.
        XCTAssertEqual(paths, [refined])
        XCTAssertEqual(shape.style.fill, SVGPaint.none)
        XCTAssertEqual(shape.style.stroke, SVGPaint.color(1, 1, 1))
        XCTAssertEqual(shape.style.strokeWidth ?? -1, 1.5, accuracy: 1e-9)
        XCTAssertEqual(shape.style.effective("stroke-linecap"), StyleValue.keyword("round"))
        XCTAssertEqual(shape.attributes.first, SVGAttribute("id", "s0"))
    }

    func testFillPrimitivesStayPrimitives() {
        let doc = VectorDocument(
            width: 24, height: 24,
            elements: [
                .fill(
                    FillShape(
                        id: "f0", color: (237, 32, 36),
                        geometry: .circle(center: Pt(12, 12), radius: 9))),
                .fill(
                    FillShape(
                        id: "f1", color: (1, 1, 1),
                        geometry: .rect(
                            center: Pt(12, 12), w: 10, h: 6, rotation: 0, cornerRadius: 2))),
            ])
        let out = Model2Bridge.document(from: doc)
        guard case .shape(let circle) = out.nodes[0] else { return XCTFail() }
        guard case .circle(let c, let r) = circle.kind else { return XCTFail() }
        XCTAssertEqual(c, Pt(12, 12))
        XCTAssertEqual(r, 9)
        XCTAssertEqual(circle.style.fill, SVGPaint.color(237, 32, 36))
        guard case .shape(let rect) = out.nodes[1] else { return XCTFail() }
        guard case .rect(let x, let y, let w, let h, let rx, _) = rect.kind else { return XCTFail() }
        XCTAssertEqual(x, 7)
        XCTAssertEqual(y, 9)
        XCTAssertEqual(w, 10)
        XCTAssertEqual(h, 6)
        XCTAssertEqual(rx, 2)
        XCTAssertNil(rect.transform)
    }

    func testRotatedPrimitiveGetsTransform() {
        let doc = VectorDocument(
            width: 24, height: 24,
            elements: [
                .fill(
                    FillShape(
                        id: "f0", color: (1, 1, 1),
                        geometry: .ellipse(
                            center: Pt(12, 12), rx: 8, ry: 4, rotation: .pi / 4)))
            ])
        let out = Model2Bridge.document(from: doc)
        guard case .shape(let shape) = out.nodes[0] else { return XCTFail() }
        XCTAssertEqual(shape.transform?.raw, "rotate(45 12 12)")
        XCTAssertNotNil(shape.transform?.matrix)
    }

    func testRefinedFillKeepsGeometryAndEvenOddRule() {
        let outer = RefinedPath(
            start: Pt(2, 2),
            segments: [.line(to: Pt(22, 2)), .line(to: Pt(22, 22)), .line(to: Pt(2, 22))],
            closed: true)
        let hole = RefinedPath(
            start: Pt(8, 8),
            segments: [.line(to: Pt(16, 8)), .line(to: Pt(16, 16)), .line(to: Pt(8, 16))],
            closed: true)
        let doc = VectorDocument(
            width: 24, height: 24,
            elements: [
                .fill(FillShape(id: "f0", color: (1, 1, 1), geometry: .refined([outer, hole])))
            ])
        let out = Model2Bridge.document(from: doc)
        guard case .shape(let shape) = out.nodes[0] else { return XCTFail() }
        guard case .path(let paths) = shape.kind else { return XCTFail() }
        XCTAssertEqual(paths, [outer, hole])
        XCTAssertEqual(shape.style.effective("fill-rule"), StyleValue.keyword("evenodd"))
    }

    func testLegacyRingsBecomeCubicPaths() {
        let ring = [Pt(2, 2), Pt(22, 2), Pt(22, 22), Pt(2, 22)]
        let doc = VectorDocument(
            width: 24, height: 24,
            elements: [.fill(FillShape(id: "f0", color: (1, 1, 1), rings: [ring]))])
        let out = Model2Bridge.document(from: doc, smoothing: 1)
        guard case .shape(let shape) = out.nodes[0] else { return XCTFail() }
        guard case .path(let paths) = shape.kind else { return XCTFail() }
        XCTAssertEqual(paths.count, 1)
        XCTAssertTrue(paths[0].closed)
        XCTAssertGreaterThanOrEqual(paths[0].segments.count, 3)
        for seg in paths[0].segments {
            guard case .cubic = seg else { return XCTFail("rings smooth to cubics") }
        }
    }

    func testGradientsBecomeDefsPlusReference() {
        let gradient = LinearGradient(
            p0: Pt(0, 0), p1: Pt(0, 24),
            stops: [
                GradientStop(color: (1, 1, 1), offset: 0),
                GradientStop(color: (237, 32, 36), offset: 1),
            ])
        let doc = VectorDocument(
            width: 24, height: 24,
            elements: [
                .fill(
                    FillShape(
                        id: "f0", paint: .linear(gradient),
                        geometry: .circle(center: Pt(12, 12), radius: 9)))
            ])
        let out = Model2Bridge.document(from: doc)
        XCTAssertEqual(out.nodes.count, 2)
        guard case .raw(let defs) = out.nodes[0] else { return XCTFail() }
        XCTAssertTrue(defs.xml.contains("<defs>"))
        XCTAssertTrue(defs.xml.contains("linearGradient"))
        XCTAssertTrue(defs.xml.contains("id=\"grad-0\""))
        XCTAssertTrue(defs.xml.contains("#ed2024"))
        guard case .shape(let shape) = out.nodes[1] else { return XCTFail() }
        XCTAssertEqual(shape.style.fill, SVGPaint.reference("grad-0"))
    }

    func testBridgedDocumentWritesValidSVG() {
        let doc = VectorDocument(
            width: 24, height: 24,
            elements: [
                .fill(
                    FillShape(
                        id: "f0", color: (237, 32, 36),
                        geometry: .circle(center: Pt(12, 12), radius: 9))),
                .stroke(
                    StrokePath(
                        id: "s0", color: (1, 1, 1), width: 1.5, closed: false,
                        points: [Pt(2, 2), Pt(20, 2)], cap: .round,
                        refined: RefinedPath(
                            start: Pt(2, 2), segments: [.line(to: Pt(20, 2))], closed: false))),
            ])
        let text = SVGWriter.write(Model2Bridge.document(from: doc))
        XCTAssertTrue(text.contains("viewBox=\"0 0 24 24\""))
        XCTAssertTrue(text.contains("<circle"))
        XCTAssertTrue(text.contains("stroke=\"#010101\""))
        // And it reads back through the editor pipeline.
        XCTAssertNoThrow(try SVGReader.read(text))
    }
}
