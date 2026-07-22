import XCTest

@testable import FekthorKit

final class SVGPathDataTests: XCTestCase {
    func assertPt(_ p: Pt, _ x: Double, _ y: Double, accuracy: Double = 1e-9,
                  file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(p.x, x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(p.y, y, accuracy: accuracy, file: file, line: line)
    }

    // MARK: - Numbers

    func testNumberFormatting() {
        XCTAssertEqual(SVGNum.format(7), "7")
        XCTAssertEqual(SVGNum.format(7.5), "7.5")
        XCTAssertEqual(SVGNum.format(7.333), "7.33")
        XCTAssertEqual(SVGNum.format(12.00), "12")
        XCTAssertEqual(SVGNum.format(0.5), ".5")
        XCTAssertEqual(SVGNum.format(-0.5), "-.5")
        XCTAssertEqual(SVGNum.format(-0.001), "0")
        XCTAssertEqual(SVGNum.format(0), "0")
        XCTAssertEqual(SVGNum.format(-0.0), "0")
    }

    // MARK: - Basic commands

    func testAbsoluteMoveLine() throws {
        let paths = try SVGPathData.parse("M4 12L20 12")
        XCTAssertEqual(paths.count, 1)
        assertPt(paths[0].start, 4, 12)
        XCTAssertEqual(paths[0].segments.count, 1)
        XCTAssertFalse(paths[0].closed)
        guard case .line(let to) = paths[0].segments[0] else { return XCTFail() }
        assertPt(to, 20, 12)
    }

    func testRelativeCommands() throws {
        let paths = try SVGPathData.parse("m4 12l16 0")
        assertPt(paths[0].start, 4, 12)
        guard case .line(let to) = paths[0].segments[0] else { return XCTFail() }
        assertPt(to, 20, 12)
    }

    func testHorizontalVertical() throws {
        let paths = try SVGPathData.parse("M0 0H10V5h-2v-1")
        let ends = paths[0].segments.map { $0.endPoint }
        XCTAssertEqual(ends.count, 4)
        assertPt(ends[0], 10, 0)
        assertPt(ends[1], 10, 5)
        assertPt(ends[2], 8, 5)
        assertPt(ends[3], 8, 4)
    }

    func testImplicitRepeats() throws {
        // Extra moveto pairs continue as lineto.
        let paths = try SVGPathData.parse("M0 0 10 10 20 0")
        XCTAssertEqual(paths[0].segments.count, 2)
        assertPt(paths[0].segments[0].endPoint, 10, 10)
        assertPt(paths[0].segments[1].endPoint, 20, 0)
    }

    func testCompactNumbers() throws {
        let paths = try SVGPathData.parse("M.5 0L5e-2 1")
        assertPt(paths[0].start, 0.5, 0)
        assertPt(paths[0].segments[0].endPoint, 0.05, 1)
    }

    func testNegativeNumberRuns() throws {
        // A '-' sign separates numbers without whitespace.
        let paths = try SVGPathData.parse("M1-2L-3-4")
        assertPt(paths[0].start, 1, -2)
        assertPt(paths[0].segments[0].endPoint, -3, -4)
    }

    // MARK: - Curves

    func testCubicAndSmooth() throws {
        let paths = try SVGPathData.parse("M0 0C1 2 3 4 5 6S7 8 9 10")
        XCTAssertEqual(paths[0].segments.count, 2)
        guard case .cubic(let c1, _, _) = paths[0].segments[1] else { return XCTFail() }
        // S reflects the previous C's second control (3,4) about (5,6).
        assertPt(c1, 7, 8)
    }

    func testSmoothWithoutPreviousCubicUsesCurrentPoint() throws {
        let paths = try SVGPathData.parse("M1 1S3 3 5 1")
        guard case .cubic(let c1, _, _) = paths[0].segments[0] else { return XCTFail() }
        assertPt(c1, 1, 1)
    }

    func testQuadraticElevation() throws {
        let paths = try SVGPathData.parse("M0 0Q4 8 8 0")
        guard case .cubic(let c1, let c2, let to) = paths[0].segments[0] else { return XCTFail() }
        assertPt(c1, 8.0 / 3.0, 16.0 / 3.0, accuracy: 1e-9)
        assertPt(c2, 16.0 / 3.0, 16.0 / 3.0, accuracy: 1e-9)
        assertPt(to, 8, 0)
    }

    func testSmoothQuadraticReflection() throws {
        let paths = try SVGPathData.parse("M0 0Q4 8 8 0T16 0")
        XCTAssertEqual(paths[0].segments.count, 2)
        guard case .cubic(let c1, _, let to) = paths[0].segments[1] else { return XCTFail() }
        assertPt(to, 16, 0)
        // Reflected control is (12,-8): the elevated c1 must dip below y=0.
        XCTAssertLessThan(c1.y, 0)
    }

    // MARK: - Arcs

    func testCircularArcBecomesNativeArc() throws {
        let paths = try SVGPathData.parse("M12 3A9 9 0 0 1 21 12")
        XCTAssertEqual(paths[0].segments.count, 1)
        guard case .arc(let c, let r, _, _, let cw) = paths[0].segments[0] else {
            return XCTFail("expected a native arc")
        }
        assertPt(c, 12, 12, accuracy: 1e-6)
        XCTAssertEqual(r, 9, accuracy: 1e-6)
        XCTAssertTrue(cw)
        assertPt(paths[0].segments[0].endPoint, 21, 12, accuracy: 1e-6)
    }

    func testEllipticalArcBecomesCubics() throws {
        let paths = try SVGPathData.parse("M0 0A10 5 0 0 1 20 0")
        XCTAssertGreaterThanOrEqual(paths[0].segments.count, 2)
        for seg in paths[0].segments {
            if case .arc = seg { XCTFail("elliptical arcs must become cubics") }
        }
        assertPt(paths[0].segments.last!.endPoint, 20, 0, accuracy: 1e-9)
    }

    func testUnspacedArcFlags() throws {
        let paths = try SVGPathData.parse("M0 0a1 1 0 011 0")
        assertPt(paths[0].segments.last!.endPoint, 1, 0, accuracy: 1e-6)
    }

    func testZeroRadiusArcIsLine() throws {
        let paths = try SVGPathData.parse("M0 0A0 5 0 0 1 10 0")
        guard case .line(let to) = paths[0].segments[0] else { return XCTFail() }
        assertPt(to, 10, 0)
    }

    // MARK: - Subpaths and closure

    func testClosedSubpath() throws {
        let paths = try SVGPathData.parse("M0 0L10 0L10 10Z")
        XCTAssertTrue(paths[0].closed)
    }

    func testMultipleSubpaths() throws {
        let paths = try SVGPathData.parse("M0 0L10 0ZM5 5L6 6")
        XCTAssertEqual(paths.count, 2)
        XCTAssertTrue(paths[0].closed)
        XCTAssertFalse(paths[1].closed)
        assertPt(paths[1].start, 5, 5)
    }

    func testCommandAfterCloseStartsAtSubpathStart() throws {
        let paths = try SVGPathData.parse("M2 3L10 3ZL5 9")
        XCTAssertEqual(paths.count, 2)
        assertPt(paths[1].start, 2, 3)
        assertPt(paths[1].segments[0].endPoint, 5, 9)
    }

    func testGarbageThrows() {
        XCTAssertThrowsError(try SVGPathData.parse("L10 0"))
        XCTAssertThrowsError(try SVGPathData.parse("M0 0X9"))
        XCTAssertThrowsError(try SVGPathData.parse("M0 0L"))
        // Parameters after closepath must error, not loop forever.
        XCTAssertThrowsError(try SVGPathData.parse("M0 0Z1"))
        XCTAssertThrowsError(try SVGPathData.parse("M0 0L5 5z 3 4"))
    }

    // MARK: - Serialisation

    func testSerializeIsStableUnderReparse() throws {
        let samples = [
            "M4 12L20 12",
            "M0 0C1 2 3 4 5 6S7 8 9 10",
            "M0 0Q4 8 8 0T16 0",
            "M12 3A9 9 0 0 1 21 12",
            "M0 0L10 0L10 10ZM5 5L6 6",
            "M.5 0L5e-2 1",
        ]
        for d in samples {
            let once = SVGPathData.serialize(try SVGPathData.parse(d))
            let twice = SVGPathData.serialize(try SVGPathData.parse(once))
            XCTAssertEqual(once, twice, d)
        }
    }

    func testSerializeArcsByDefaultEmitsCubics() throws {
        let paths = try SVGPathData.parse("M12 3A9 9 0 0 1 21 12")
        let d = SVGPathData.serialize(paths)
        XCTAssertFalse(d.contains("A"))
        XCTAssertTrue(d.contains("C"))
        let arcs = SVGPathData.serialize(paths, emitArcs: true)
        XCTAssertTrue(arcs.contains("A"))
    }

    func testSerializeNoNegativeZero() {
        let path = RefinedPath(
            start: Pt(-0.0001, 0), segments: [.line(to: Pt(5, -0.0))], closed: false)
        let d = SVGPathData.serialize([path])
        XCTAssertFalse(d.contains("-0"), d)
    }
}

final class SVGStyleTests: XCTestCase {
    func testTypedPaints() {
        XCTAssertEqual(SVGStyle.parsePaint("none"), SVGPaint.none)
        XCTAssertEqual(SVGStyle.parsePaint("#010101"), SVGPaint.color(1, 1, 1))
        XCTAssertEqual(SVGStyle.parsePaint("#ed2024"), SVGPaint.color(0xED, 0x20, 0x24))
        XCTAssertEqual(SVGStyle.parsePaint("url(#grad-0)"), SVGPaint.reference("grad-0"))
    }

    func testVerbatimPaints() {
        // Anything whose canonical form differs from the source stays raw.
        XCTAssertEqual(SVGStyle.parsePaint("#ED2024"), SVGPaint.raw("#ED2024"))
        XCTAssertEqual(SVGStyle.parsePaint("#abc"), SVGPaint.raw("#abc"))
        XCTAssertEqual(SVGStyle.parsePaint("currentColor"), SVGPaint.raw("currentColor"))
        XCTAssertEqual(
            SVGStyle.parsePaint("var(--icon-accent, #ed2024)"),
            SVGPaint.raw("var(--icon-accent, #ed2024)"))
        XCTAssertEqual(SVGStyle.parsePaint("black"), SVGPaint.raw("black"))
    }

    func testTypedValues() {
        XCTAssertEqual(
            SVGStyle.value(property: "stroke-width", string: "1.5"),
            StyleValue.number(1.5, unit: ""))
        XCTAssertEqual(
            SVGStyle.value(property: "stroke-linecap", string: "round"),
            StyleValue.keyword("round"))
        XCTAssertEqual(
            SVGStyle.value(property: "fill", string: "none"),
            StyleValue.paint(SVGPaint.none))
    }

    func testLossyValuesStayRaw() {
        // "0.5" would canonicalise to ".5", so it must stay verbatim.
        XCTAssertEqual(
            SVGStyle.value(property: "stroke-width", string: "0.5"), StyleValue.raw("0.5"))
        XCTAssertEqual(
            SVGStyle.value(property: "stroke-width", string: "1.5px"),
            StyleValue.number(1.5, unit: "px"))
        XCTAssertEqual(
            SVGStyle.value(property: "--icon-size", string: "24px"), StyleValue.raw("24px"))
    }

    func testDeclarationRoundTrip() {
        let sources = [
            "fill:none;stroke:#010101;stroke-width:1.5;stroke-linecap:round;stroke-linejoin:round",
            "stroke:#ed2024;stroke-width:.5",
            "fill:var(--icon-accent, #ed2024);--icon-size:24px",
            "stroke:currentColor;stroke-dasharray:2 3",
        ]
        for css in sources {
            let declarations = SVGStyle.parseDeclarations(css, origin: .inlineStyle)
            XCTAssertEqual(SVGStyle.serializeInline(declarations), css, css)
        }
    }

    func testSemicolonsInsideValuesDoNotSplitDeclarations() {
        let css = "fill:url(data:image/png;base64,AA==);stroke:#010101"
        let declarations = SVGStyle.parseDeclarations(css, origin: .inlineStyle)
        XCTAssertEqual(declarations.count, 2)
        XCTAssertEqual(
            declarations[0].value, StyleValue.raw("url(data:image/png;base64,AA==)"))
        XCTAssertEqual(SVGStyle.serializeInline(declarations), css)

        let quoted = "font-family:'A;B';stroke:#010101"
        let quotedDeclarations = SVGStyle.parseDeclarations(quoted, origin: .inlineStyle)
        XCTAssertEqual(quotedDeclarations.count, 2)
        XCTAssertEqual(quotedDeclarations[0].value, StyleValue.raw("'A;B'"))
        XCTAssertEqual(SVGStyle.serializeInline(quotedDeclarations), quoted)
    }

    func testStylesheetClassRules() {
        let css = """
            /* corpus style */
            .st0{fill:none;stroke:#010101}
            .st1, .st2 { stroke-width: 1.5 }
            #ignored { fill: red }
            """
        let map = SVGStyle.parseStylesheet(css)
        XCTAssertEqual(map.count, 3)
        XCTAssertEqual(map["st0"]?.count, 2)
        XCTAssertEqual(map["st0"]?[1].value, StyleValue.paint(SVGPaint.color(1, 1, 1)))
        XCTAssertEqual(map["st1"]?.count, 1)
        XCTAssertEqual(map["st2"]?.count, 1)
        XCTAssertNil(map["ignored"])
        XCTAssertEqual(map["st0"]?[0].origin, StyleOrigin.stylesheet)
    }
}
