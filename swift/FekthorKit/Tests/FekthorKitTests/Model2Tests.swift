import XCTest

@testable import FekthorKit

final class Model2Tests: XCTestCase {
    func testConstructionAndEquality() {
        let path = RefinedPath(
            start: Pt(4, 12), segments: [.line(to: Pt(20, 12))], closed: false)
        let style = NodeStyle([
            StyleDeclaration("fill", .paint(SVGPaint.none), origin: .inlineStyle),
            StyleDeclaration("stroke", .paint(.color(1, 1, 1)), origin: .inlineStyle),
            StyleDeclaration("stroke-width", .number(1.5, unit: ""), origin: .inlineStyle),
        ])
        let shape = ShapeNode(kind: .path([path]), style: style)
        let doc = GraphicDocument(
            viewBox: ViewBox(minX: 0, minY: 0, width: 24, height: 24),
            rootAttributes: [
                SVGAttribute("xmlns", "http://www.w3.org/2000/svg"),
                SVGAttribute("viewBox", "0 0 24 24"),
            ],
            hadXMLDeclaration: true,
            nodes: [
                .shape(shape),
                .group(GroupNode(children: [.shape(shape)])),
                .raw(RawNode(xml: "<defs></defs>")),
            ])
        XCTAssertEqual(doc, doc)
        var other = doc
        other.nodes.removeLast()
        XCTAssertNotEqual(doc, other)
    }

    func testPrimitivesStayPrimitives() {
        let circle = ShapeNode(kind: .circle(center: Pt(12, 12), radius: 9))
        guard case .circle(let c, let r) = circle.kind else { return XCTFail() }
        XCTAssertEqual(c, Pt(12, 12))
        XCTAssertEqual(r, 9)
        let rect = ShapeNode(kind: .rect(x: 3, y: 3, width: 18, height: 18, rx: 2, ry: nil))
        guard case .rect(_, _, _, _, let rx, let ry) = rect.kind else { return XCTFail() }
        XCTAssertEqual(rx, 2)
        XCTAssertNil(ry)
    }

    func testEffectiveStylePriority() {
        // Presentation attribute < stylesheet < inline style.
        var style = NodeStyle([
            StyleDeclaration("stroke", .paint(.color(1, 1, 1)), origin: .attribute),
            StyleDeclaration("stroke", .paint(.color(0xED, 0x20, 0x24)), origin: .stylesheet),
        ])
        XCTAssertEqual(style.stroke, SVGPaint.color(0xED, 0x20, 0x24))
        style.declarations.append(
            StyleDeclaration("stroke", .paint(.color(9, 9, 9)), origin: .inlineStyle))
        XCTAssertEqual(style.stroke, SVGPaint.color(9, 9, 9))
        // Later declaration wins on equal rank.
        let repeated = NodeStyle([
            StyleDeclaration("fill", .paint(SVGPaint.none), origin: .inlineStyle),
            StyleDeclaration("fill", .paint(.color(1, 2, 3)), origin: .inlineStyle),
        ])
        XCTAssertEqual(repeated.fill, SVGPaint.color(1, 2, 3))
    }

    func testFillAndStrokeCoexist() {
        let style = NodeStyle([
            StyleDeclaration("fill", .paint(.color(255, 255, 255)), origin: .inlineStyle),
            StyleDeclaration("stroke", .paint(.color(1, 1, 1)), origin: .inlineStyle),
        ])
        XCTAssertEqual(style.fill, SVGPaint.color(255, 255, 255))
        XCTAssertEqual(style.stroke, SVGPaint.color(1, 1, 1))
    }

    func testRawValuesPreserved() {
        let style = NodeStyle([
            StyleDeclaration("stroke", .raw("currentColor"), origin: .attribute),
            StyleDeclaration("fill", .raw("var(--icon-accent, #ed2024)"), origin: .inlineStyle),
            StyleDeclaration("--icon-size", .raw("24px"), origin: .inlineStyle),
        ])
        XCTAssertEqual(style.stroke, SVGPaint.raw("currentColor"))
        XCTAssertEqual(style.fill, SVGPaint.raw("var(--icon-accent, #ed2024)"))
        XCTAssertEqual(style.effective("--icon-size"), StyleValue.raw("24px"))
    }

    func testNumberAccessorReadsRawValues() {
        let style = NodeStyle([
            StyleDeclaration("stroke-width", .raw("1.5px"), origin: .inlineStyle)
        ])
        XCTAssertEqual(style.strokeWidth ?? -1, 1.5, accuracy: 1e-9)
    }

    func testSetReplacesWritableDeclarationInPlace() {
        var style = NodeStyle([
            StyleDeclaration("stroke", .paint(.color(1, 1, 1)), origin: .inlineStyle),
            StyleDeclaration("stroke-width", .number(1.5, unit: ""), origin: .inlineStyle),
        ])
        style.set("stroke", .paint(.color(0xED, 0x20, 0x24)))
        XCTAssertEqual(style.declarations.count, 2)
        XCTAssertEqual(style.stroke, SVGPaint.color(0xED, 0x20, 0x24))
        // Order is unchanged: stroke stays first.
        XCTAssertEqual(style.declarations[0].property, "stroke")
    }

    func testSetOverridesStylesheetWithInline() {
        // A stylesheet value lives in the preserved <style> block, so setting
        // it must append an inline override rather than mutate it.
        var style = NodeStyle([
            StyleDeclaration("stroke", .paint(.color(1, 1, 1)), origin: .stylesheet)
        ])
        style.set("stroke", .paint(.color(9, 9, 9)))
        XCTAssertEqual(style.declarations.count, 2)
        XCTAssertEqual(style.declarations[1].origin, StyleOrigin.inlineStyle)
        XCTAssertEqual(style.stroke, SVGPaint.color(9, 9, 9))
    }

    func testTransformParsing() {
        let t = Transform2D(raw: "translate(3, 4)")
        XCTAssertEqual(t.raw, "translate(3, 4)")
        XCTAssertEqual(t.matrix?.tx ?? -1, 3, accuracy: 1e-9)
        XCTAssertEqual(t.matrix?.ty ?? -1, 4, accuracy: 1e-9)

        let rot = Transform2D(raw: "rotate(90 12 12)")
        let p = rot.matrix?.apply(Pt(12, 3)) ?? Pt(0, 0)
        XCTAssertEqual(p.x, 21, accuracy: 1e-6)
        XCTAssertEqual(p.y, 12, accuracy: 1e-6)

        let combo = Transform2D(raw: "translate(10 0) scale(2)")
        let q = combo.matrix?.apply(Pt(1, 1)) ?? Pt(0, 0)
        XCTAssertEqual(q.x, 12, accuracy: 1e-9)
        XCTAssertEqual(q.y, 2, accuracy: 1e-9)

        let matrix = Transform2D(raw: "matrix(1 0 0 1 5 6)")
        XCTAssertEqual(matrix.matrix?.tx ?? 0, 5, accuracy: 1e-9)

        // Unknown functions parse to nil but keep the verbatim string.
        let unknown = Transform2D(raw: "perspective(200)")
        XCTAssertNil(unknown.matrix)
        XCTAssertEqual(unknown.raw, "perspective(200)")
    }
}
