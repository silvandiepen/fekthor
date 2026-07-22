import XCTest

@testable import FekthorKit

final class WorkfileTests: XCTestCase {
    func sample() -> Workfile {
        Workfile(
            folder: Workfile.FolderReference(
                path: "/Users/x/Repositories/open-icon/src/icons",
                bookmark: Data([1, 2, 3])),
            artboards: [
                Workfile.Artboard(
                    name: "arrow-right",
                    svg: "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\"><path d=\"M4 12L20 12\"/></svg>")
            ],
            categories: ["arrows", "ui"],
            exportProfiles: [Workfile.ExportProfile(name: "lib")],
            styleTokens: [
                Workfile.StyleToken(name: "outline", color: "#010101"),
                Workfile.StyleToken(name: "accent", color: "#ed2024"),
            ],
            containers: [
                Workfile.ContainerSlot(icon: "circle-container", x: 5, y: 5, width: 14, height: 14, fit: "contain")
            ])
    }

    func testRoundTrip() throws {
        let original = sample()
        let decoded = try Workfile.decode(try original.encode())
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.version, Workfile.currentVersion)
    }

    func testDeterministicEncoding() throws {
        let a = try sample().encode()
        let b = try sample().encode()
        XCTAssertEqual(a, b)
        // Sorted keys: "artboards" precedes "version" in the output.
        let text = String(data: a, encoding: .utf8) ?? ""
        let artboardsIndex = text.range(of: "\"artboards\"")?.lowerBound
        let versionIndex = text.range(of: "\"version\"")?.lowerBound
        XCTAssertNotNil(artboardsIndex)
        XCTAssertNotNil(versionIndex)
        if let a = artboardsIndex, let v = versionIndex { XCTAssertLessThan(a, v) }
    }

    func testEmbeddedSVGStaysReadableText() throws {
        let data = try sample().encode()
        let text = String(data: data, encoding: .utf8) ?? ""
        // Slashes unescaped: the SVG text is legible in the JSON.
        XCTAssertTrue(text.contains("</svg>"))
        // And it feeds straight back into the single geometry path.
        let decoded = try Workfile.decode(data)
        let svg = decoded.artboards?.first?.svg ?? ""
        XCTAssertNoThrow(try SVGReader.read(svg))
    }

    func testUnknownKeysAreTolerated() throws {
        let json = """
            {
              "version": 1,
              "categories": ["arrows"],
              "futureSection": {"anything": [1, 2, 3]},
              "anotherUnknown": "ok"
            }
            """
        let workfile = try Workfile.decode(Data(json.utf8))
        XCTAssertEqual(workfile.version, 1)
        XCTAssertEqual(workfile.categories, ["arrows"])
        XCTAssertNil(workfile.folder)
        XCTAssertNil(workfile.artboards)
    }

    func testMinimalWorkfile() throws {
        let workfile = try Workfile.decode(Data("{\"version\": 1}".utf8))
        XCTAssertEqual(workfile, Workfile())
    }
}
