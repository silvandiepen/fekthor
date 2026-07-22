import XCTest

@testable import FekthorKit

final class SVGReaderTests: XCTestCase {
    func testMinimalIcon() throws {
        let doc = try SVGReader.read(
            """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M4 12L20 12" style="fill:none;stroke:#010101;stroke-width:1.5"/></svg>
            """)
        XCTAssertFalse(doc.hadXMLDeclaration)
        XCTAssertEqual(doc.viewBox?.width, 24)
        XCTAssertEqual(doc.rootAttributes.count, 2)
        XCTAssertEqual(doc.rootAttributes[0].name, "xmlns")
        XCTAssertEqual(doc.nodes.count, 1)
        guard case .shape(let shape) = doc.nodes[0] else { return XCTFail() }
        guard case .path(let paths) = shape.kind else { return XCTFail() }
        XCTAssertEqual(paths.count, 1)
        XCTAssertEqual(shape.style.fill, SVGPaint.none)
        XCTAssertEqual(shape.style.stroke, SVGPaint.color(1, 1, 1))
        XCTAssertEqual(shape.style.strokeWidth ?? -1, 1.5, accuracy: 1e-9)
        XCTAssertEqual(shape.style.declarations.map(\.origin), [.inlineStyle, .inlineStyle, .inlineStyle])
    }

    func testXMLDeclarationDetected() throws {
        let with = try SVGReader.read(
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>")
        XCTAssertTrue(with.hadXMLDeclaration)
        let without = try SVGReader.read("<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>")
        XCTAssertFalse(without.hadXMLDeclaration)
    }

    func testPrimitives() throws {
        let doc = try SVGReader.read(
            """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
              <rect x="3" y="3" width="18" height="18" rx="2" fill="none" stroke="#010101"/>
              <circle cx="12" cy="12" r="9" stroke="#010101"/>
              <ellipse cx="12" cy="12" rx="9" ry="4"/>
              <line x1="5" y1="12" x2="19" y2="12"/>
              <polyline points="2,12 6,4 10,20"/>
              <polygon points="12,2 22,22 2,22"/>
            </svg>
            """)
        let shapes: [ShapeNode] = doc.nodes.compactMap {
            if case .shape(let s) = $0 { return s } else { return nil }
        }
        XCTAssertEqual(shapes.count, 6)
        guard case .rect(let x, _, let w, _, let rx, let ry) = shapes[0].kind else { return XCTFail() }
        XCTAssertEqual(x, 3)
        XCTAssertEqual(w, 18)
        XCTAssertEqual(rx, 2)
        XCTAssertNil(ry)
        guard case .circle(let c, let r) = shapes[1].kind else { return XCTFail() }
        XCTAssertEqual(c, Pt(12, 12))
        XCTAssertEqual(r, 9)
        guard case .ellipse(_, let erx, let ery) = shapes[2].kind else { return XCTFail() }
        XCTAssertEqual(erx, 9)
        XCTAssertEqual(ery, 4)
        guard case .line(let from, let to) = shapes[3].kind else { return XCTFail() }
        XCTAssertEqual(from, Pt(5, 12))
        XCTAssertEqual(to, Pt(19, 12))
        guard case .polyline(let pl) = shapes[4].kind else { return XCTFail() }
        XCTAssertEqual(pl.count, 3)
        XCTAssertEqual(pl[1], Pt(6, 4))
        guard case .polygon(let pg) = shapes[5].kind else { return XCTFail() }
        XCTAssertEqual(pg.count, 3)
        // Presentation attributes carry origin .attribute.
        XCTAssertEqual(shapes[0].style.declarations.first?.origin, StyleOrigin.attribute)
        XCTAssertEqual(shapes[0].style.fill, SVGPaint.none)
        XCTAssertEqual(shapes[0].style.stroke, SVGPaint.color(1, 1, 1))
    }

    func testGroupsRecursive() throws {
        let doc = try SVGReader.read(
            """
            <svg xmlns="http://www.w3.org/2000/svg">
              <g transform="rotate(45 12 12)" stroke="#010101">
                <line x1="12" y1="1" x2="12" y2="4"/>
                <g><circle cx="12" cy="12" r="4"/></g>
              </g>
            </svg>
            """)
        guard case .group(let g) = doc.nodes[0] else { return XCTFail() }
        XCTAssertEqual(g.transform?.raw, "rotate(45 12 12)")
        XCTAssertNotNil(g.transform?.matrix)
        XCTAssertEqual(g.style.stroke, SVGPaint.color(1, 1, 1))
        XCTAssertEqual(g.children.count, 2)
        guard case .group(let inner) = g.children[1] else { return XCTFail() }
        XCTAssertEqual(inner.children.count, 1)
    }

    func testUnknownElementsAndDefsAreRawVerbatim() throws {
        let doc = try SVGReader.read(
            """
            <svg xmlns="http://www.w3.org/2000/svg">
              <defs><linearGradient id="grad-0"><stop offset="0" stop-color="#010101"/></linearGradient></defs>
              <text x="2" y="2">hi</text>
              <path d="M0 0L2 2"/>
            </svg>
            """)
        let raws: [RawNode] = doc.nodes.compactMap {
            if case .raw(let r) = $0 { return r } else { return nil }
        }
        XCTAssertEqual(raws.count, 2)
        XCTAssertTrue(raws[0].xml.contains("<defs"))
        XCTAssertTrue(raws[0].xml.contains("grad-0"))
        XCTAssertTrue(raws[1].xml.contains("<text"))
    }

    func testUnparseableShapeFallsBackToRaw() throws {
        let doc = try SVGReader.read(
            """
            <svg xmlns="http://www.w3.org/2000/svg"><path d="Q broken"/><rect width="oops" height="3"/></svg>
            """)
        XCTAssertEqual(doc.nodes.count, 2)
        for node in doc.nodes {
            guard case .raw(let raw) = node else { return XCTFail("expected raw fallback") }
            XCTAssertFalse(raw.xml.isEmpty)
        }
    }

    func testClassResolverRendersEffectiveStyleAndKeepsStyleBlock() throws {
        let doc = try SVGReader.read(
            """
            <svg xmlns="http://www.w3.org/2000/svg">
              <style>.st0{fill:none;stroke:#010101}</style>
              <path class="st0" d="M0 0L2 2"/>
            </svg>
            """)
        // The <style> block survives verbatim…
        guard case .raw(let raw) = doc.nodes[0] else { return XCTFail() }
        XCTAssertTrue(raw.xml.contains(".st0"))
        // …and the shape still knows its effective style, tagged stylesheet.
        guard case .shape(let shape) = doc.nodes[1] else { return XCTFail() }
        XCTAssertEqual(shape.style.stroke, SVGPaint.color(1, 1, 1))
        XCTAssertEqual(shape.style.fill, SVGPaint.none)
        XCTAssertTrue(shape.style.declarations.allSatisfy { $0.origin == .stylesheet })
        // The class attribute remains an ordinary attribute.
        XCTAssertTrue(shape.attributes.contains(SVGAttribute("class", "st0")))
    }

    func testInlineStyleBeatsStylesheetBeatsAttribute() throws {
        let doc = try SVGReader.read(
            """
            <svg xmlns="http://www.w3.org/2000/svg">
              <style>.st0{stroke:#222222}</style>
              <path class="st0" stroke="#111111" style="stroke:#333333" d="M0 0L2 2"/>
            </svg>
            """)
        guard case .shape(let shape) = doc.nodes[1] else { return XCTFail() }
        XCTAssertEqual(shape.style.stroke, SVGPaint.color(0x33, 0x33, 0x33))
    }

    func testNotAnSVGThrows() {
        XCTAssertThrowsError(try SVGReader.read("<html><body/></html>"))
        XCTAssertThrowsError(try SVGReader.read("not xml at all"))
    }

    func testUnknownAttributesSurviveAsLeftovers() throws {
        let doc = try SVGReader.read(
            """
            <svg xmlns="http://www.w3.org/2000/svg"><path id="a" data-name="Arrow" clip-path="url(#c)" d="M0 0L2 2"/></svg>
            """)
        guard case .shape(let shape) = doc.nodes[0] else { return XCTFail() }
        XCTAssertEqual(shape.attributes.count, 3)
        XCTAssertEqual(shape.attributes[0], SVGAttribute("id", "a"))
        XCTAssertEqual(shape.attributes[1], SVGAttribute("data-name", "Arrow"))
        XCTAssertEqual(shape.attributes[2], SVGAttribute("clip-path", "url(#c)"))
    }
}
