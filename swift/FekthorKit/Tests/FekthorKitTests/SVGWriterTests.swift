import XCTest

@testable import FekthorKit

final class SVGWriterTests: XCTestCase {
    /// A corpus-style icon: XML declaration, inline styles, primitives, a
    /// group, defs, and only writer-canonical numbers.
    static let icon = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">
          <defs><clipPath id="c"><rect width="24" height="24"/></clipPath></defs>
          <path d="M4 12L20 12" style="fill:none;stroke:#010101;stroke-width:1.5;stroke-linecap:round"/>
          <circle cx="12" cy="12" r="9" style="fill:none;stroke:#ed2024"/>
          <g id="grid">
            <rect x="3" y="3" width="7" height="7" rx="1" style="fill:none;stroke:#010101"/>
            <rect x="14" y="3" width="7" height="7" rx="1" style="fill:none;stroke:#010101"/>
          </g>
        </svg>
        """

    func testDeterminism() throws {
        let doc = try SVGReader.read(Self.icon)
        XCTAssertEqual(SVGWriter.write(doc), SVGWriter.write(doc))
        let again = try SVGReader.read(Self.icon)
        XCTAssertEqual(doc, again)
    }

    func testIdempotence() throws {
        let once = SVGWriter.write(try SVGReader.read(Self.icon))
        let twice = SVGWriter.write(try SVGReader.read(once))
        XCTAssertEqual(once, twice)
    }

    func testModelEqualityAfterRewrite() throws {
        let doc = try SVGReader.read(Self.icon)
        let rewritten = try SVGReader.read(SVGWriter.write(doc))
        XCTAssertEqual(doc, rewritten)
    }

    func testXMLDeclarationOnlyWhenSourceHadOne() throws {
        let with = SVGWriter.write(try SVGReader.read(Self.icon))
        XCTAssertTrue(with.hasPrefix("<?xml"))
        let bare = "<svg xmlns=\"http://www.w3.org/2000/svg\"><path d=\"M0 0L2 2\"/></svg>"
        let without = SVGWriter.write(try SVGReader.read(bare))
        XCTAssertFalse(without.contains("<?xml"))
    }

    func testRootAttributesVerbatim() throws {
        let out = SVGWriter.write(try SVGReader.read(Self.icon))
        XCTAssertTrue(
            out.contains(
                "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"24\" height=\"24\" viewBox=\"0 0 24 24\">"))
    }

    func testSynthesisedRootForProgrammaticDocuments() {
        let doc = GraphicDocument(
            viewBox: ViewBox(minX: 0, minY: 0, width: 24, height: 24),
            nodes: [.shape(ShapeNode(kind: .circle(center: Pt(12, 12), radius: 9)))])
        let out = SVGWriter.write(doc)
        XCTAssertTrue(out.contains("xmlns=\"http://www.w3.org/2000/svg\""))
        XCTAssertTrue(out.contains("viewBox=\"0 0 24 24\""))
        XCTAssertTrue(out.contains("<circle cx=\"12\" cy=\"12\" r=\"9\"/>"))
    }

    func testPrimitivesStayNativeElements() throws {
        let out = SVGWriter.write(try SVGReader.read(Self.icon))
        XCTAssertTrue(out.contains("<circle "))
        XCTAssertTrue(out.contains("<rect "))
        XCTAssertTrue(out.contains("rx=\"1\""))
        XCTAssertFalse(out.contains("<circle cx=\"12\" cy=\"12\" r=\"9\" d="))
    }

    func testDefsPreservedVerbatim() throws {
        let out = SVGWriter.write(try SVGReader.read(Self.icon))
        XCTAssertTrue(out.contains("clipPath"))
        XCTAssertTrue(out.contains("id=\"c\""))
    }

    func testArcsBecomeCubicsByDefault() throws {
        let src =
            "<svg xmlns=\"http://www.w3.org/2000/svg\"><path d=\"M12 3A9 9 0 0 1 21 12\" style=\"fill:none;stroke:#010101\"/></svg>"
        let doc = try SVGReader.read(src)
        let out = SVGWriter.write(doc)
        XCTAssertFalse(out.contains("A9"))
        XCTAssertTrue(out.contains("C"))
        let arcs = SVGWriter.write(doc, options: SVGWriteOptions(emitArcs: true))
        XCTAssertTrue(arcs.contains("A9 9 0 0 1 21 12"))
        // Idempotent under the default option too.
        let twice = SVGWriter.write(try SVGReader.read(out))
        XCTAssertEqual(out, twice)
    }

    func testStyleDeclarationOrderPreserved() throws {
        let src =
            "<svg xmlns=\"http://www.w3.org/2000/svg\"><path d=\"M0 0L2 2\" style=\"stroke:#010101;fill:none;stroke-width:1.5\"/></svg>"
        let out = SVGWriter.write(try SVGReader.read(src))
        XCTAssertTrue(out.contains("style=\"stroke:#010101;fill:none;stroke-width:1.5\""))
    }

    func testPresentationAttributesStayAttributes() throws {
        let src =
            "<svg xmlns=\"http://www.w3.org/2000/svg\"><path d=\"M0 0L2 2\" fill=\"none\" stroke=\"currentColor\"/></svg>"
        let out = SVGWriter.write(try SVGReader.read(src))
        XCTAssertTrue(out.contains("fill=\"none\" stroke=\"currentColor\""))
        XCTAssertFalse(out.contains("style="))
    }

    func testAttributeEscaping() throws {
        let src =
            "<svg xmlns=\"http://www.w3.org/2000/svg\"><path data-name=\"A&amp;B &quot;q&quot;\" d=\"M0 0L2 2\"/></svg>"
        let doc = try SVGReader.read(src)
        guard case .shape(let shape) = doc.nodes[0] else { return XCTFail() }
        XCTAssertEqual(shape.attributes.first?.value, "A&B \"q\"")
        let out = SVGWriter.write(doc)
        XCTAssertTrue(out.contains("data-name=\"A&amp;B &quot;q&quot;\""))
        XCTAssertEqual(try SVGReader.read(out), doc)
    }

    func testEmptyGroupSelfCloses() {
        let doc = GraphicDocument(nodes: [.group(GroupNode())])
        XCTAssertTrue(SVGWriter.write(doc).contains("<g/>"))
    }

    func testTransformEmittedVerbatim() throws {
        let src =
            "<svg xmlns=\"http://www.w3.org/2000/svg\"><g transform=\"rotate(45 12 12)\"><path d=\"M0 0L2 2\"/></g></svg>"
        let out = SVGWriter.write(try SVGReader.read(src))
        XCTAssertTrue(out.contains("transform=\"rotate(45 12 12)\""))
    }
}
