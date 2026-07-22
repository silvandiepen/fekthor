import XCTest

@testable import FekthorKit

/// The plan-08 round-trip corpus suite. The bundled fixtures under
/// `Fixtures/openicon/` mimic the open-icon conventions (24×24, inline
/// styles, `#010101` outline / `#ed2024` accent, stroke-based, primitives,
/// arcs, one class-styled file); drop real icons into the same folder and
/// every test here picks them up unchanged. The env-gated smoke test runs the
/// full local corpus:
/// `FEKTHOR_ICON_CORPUS=~/Repositories/_projects/open-icon/src/icons swift test`.
final class RoundTripCorpusTests: XCTestCase {
    static func fixtureURLs() -> [URL] {
        let urls =
            Bundle.module.urls(forResourcesWithExtension: "svg", subdirectory: "Fixtures/openicon")
            ?? []
        return urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func testFixturesPresent() {
        XCTAssertGreaterThanOrEqual(Self.fixtureURLs().count, 15)
    }

    func testEveryFixtureReads() throws {
        for url in Self.fixtureURLs() {
            let text = try String(contentsOf: url, encoding: .utf8)
            let doc = try SVGReader.read(text)
            XCTAssertFalse(doc.nodes.isEmpty, url.lastPathComponent)
        }
    }

    func testWriteIsDeterministic() throws {
        for url in Self.fixtureURLs() {
            let text = try String(contentsOf: url, encoding: .utf8)
            let doc = try SVGReader.read(text)
            XCTAssertEqual(SVGWriter.write(doc), SVGWriter.write(doc), url.lastPathComponent)
            XCTAssertEqual(doc, try SVGReader.read(text), url.lastPathComponent)
        }
    }

    func testWriteIsIdempotent() throws {
        // The save contract: write(read(write(read(f)))) == write(read(f)).
        for url in Self.fixtureURLs() {
            let text = try String(contentsOf: url, encoding: .utf8)
            let once = SVGWriter.write(try SVGReader.read(text))
            let twice = SVGWriter.write(try SVGReader.read(once))
            XCTAssertEqual(once, twice, url.lastPathComponent)
        }
    }

    func testRewriteKeepsModelOrDeviatesBelowTolerance() throws {
        // Normalise-on-first-save: a rewrite either reproduces the exact
        // model (corpus-canonical files) or deviates only by number
        // formatting / arc conversion — structure and styles identical,
        // geometry within 0.05 px.
        for url in Self.fixtureURLs() {
            let name = url.lastPathComponent
            let text = try String(contentsOf: url, encoding: .utf8)
            let original = try SVGReader.read(text)
            let rewritten = try SVGReader.read(SVGWriter.write(original))
            if original == rewritten { continue }
            XCTAssertEqual(signature(original), signature(rewritten), name)
            let deviation = maxDeviation(original, rewritten)
            XCTAssertLessThan(deviation, 0.05, name)
        }
    }

    func testStyleStringsRoundTripVerbatim() throws {
        for url in Self.fixtureURLs() {
            let text = try String(contentsOf: url, encoding: .utf8)
            let out = SVGWriter.write(try SVGReader.read(text))
            XCTAssertEqual(
                styleStrings(in: text), styleStrings(in: out), url.lastPathComponent)
        }
    }

    func testFullCorpusSmoke() throws {
        guard let root = ProcessInfo.processInfo.environment["FEKTHOR_ICON_CORPUS"] else {
            throw XCTSkip("FEKTHOR_ICON_CORPUS not set; skipping full-corpus smoke")
        }
        let rootURL = URL(fileURLWithPath: (root as NSString).expandingTildeInPath)
        guard
            let enumerator = FileManager.default.enumerator(
                at: rootURL, includingPropertiesForKeys: nil)
        else {
            return XCTFail("corpus not readable at \(rootURL.path)")
        }
        var count = 0
        var failures: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "svg" {
            count += 1
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                let once = SVGWriter.write(try SVGReader.read(text))
                let twice = SVGWriter.write(try SVGReader.read(once))
                if once != twice { failures.append("\(url.lastPathComponent): not idempotent") }
            } catch {
                failures.append("\(url.lastPathComponent): \(error)")
            }
        }
        XCTAssertGreaterThan(count, 0, "no .svg files under \(rootURL.path)")
        XCTAssertTrue(
            failures.isEmpty,
            "\(failures.count)/\(count) corpus failures:\n"
                + failures.prefix(20).joined(separator: "\n"))
    }

    // MARK: - Normalised comparison helpers

    /// Structure + style signature, geometry numbers excluded: tag names,
    /// attributes, style declarations and transforms, in document order.
    func signature(_ doc: GraphicDocument) -> [String] {
        var out: [String] = ["root:\(doc.rootAttributes.map { "\($0.name)=\($0.value)" }.joined(separator: " "))"]
        func styleText(_ style: NodeStyle) -> String {
            style.declarations
                .map { "\($0.origin):\($0.property):\(SVGStyle.string(from: $0.value))" }
                .joined(separator: ";")
        }
        func walk(_ nodes: [GraphicNode], depth: Int) {
            for node in nodes {
                switch node {
                case .shape(let s):
                    let attrs = s.attributes.map { "\($0.name)=\($0.value)" }.joined(separator: " ")
                    out.append(
                        "\(depth):shape:\(SVGWriter.tagName(s.kind)):\(attrs):\(styleText(s.style)):\(s.transform?.raw ?? "")")
                case .group(let g):
                    let attrs = g.attributes.map { "\($0.name)=\($0.value)" }.joined(separator: " ")
                    out.append("\(depth):group:\(attrs):\(styleText(g.style)):\(g.transform?.raw ?? "")")
                    walk(g.children, depth: depth + 1)
                case .raw(let r):
                    out.append("\(depth):raw:\(r.xml)")
                }
            }
        }
        walk(doc.nodes, depth: 0)
        return out
    }

    /// Worst symmetric point-to-polyline distance across all corresponding
    /// flattened path geometries (primitives compare exactly via signature +
    /// model equality, so only `.path` needs a tolerance).
    func maxDeviation(_ a: GraphicDocument, _ b: GraphicDocument) -> Double {
        let sa = shapes(a)
        let sb = shapes(b)
        guard sa.count == sb.count else { return .infinity }
        var worst = 0.0
        for (x, y) in zip(sa, sb) {
            let pa = flattened(x.kind)
            let pb = flattened(y.kind)
            guard pa.count == pb.count else { return .infinity }
            for (ra, rb) in zip(pa, pb) {
                worst = max(worst, polylineDistance(ra, rb))
                worst = max(worst, polylineDistance(rb, ra))
            }
        }
        return worst
    }

    func shapes(_ doc: GraphicDocument) -> [ShapeNode] {
        var out: [ShapeNode] = []
        func walk(_ nodes: [GraphicNode]) {
            for node in nodes {
                switch node {
                case .shape(let s): out.append(s)
                case .group(let g): walk(g.children)
                case .raw: break
                }
            }
        }
        walk(doc.nodes)
        return out
    }

    func flattened(_ kind: ShapeKind) -> [[Pt]] {
        guard case .path(let paths) = kind else { return [] }
        return paths.map { PathRefine.flatten(Editing.cubicized($0), cubicSamples: 24) }
    }

    /// Max over points of `a` of the distance to the nearest segment of `b`.
    func polylineDistance(_ a: [Pt], _ b: [Pt]) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return a.isEmpty && b.isEmpty ? 0 : .infinity }
        var worst = 0.0
        for p in a {
            var best = Double.infinity
            if b.count == 1 {
                best = hypot(p.x - b[0].x, p.y - b[0].y)
            }
            for i in 0..<(b.count - 1) {
                best = min(best, segmentDistance(p, b[i], b[i + 1]))
            }
            worst = max(worst, best)
        }
        return worst
    }

    func segmentDistance(_ p: Pt, _ a: Pt, _ b: Pt) -> Double {
        let vx = b.x - a.x
        let vy = b.y - a.y
        let len2 = vx * vx + vy * vy
        if len2 < 1e-18 { return hypot(p.x - a.x, p.y - a.y) }
        var t = ((p.x - a.x) * vx + (p.y - a.y) * vy) / len2
        t = max(0, min(1, t))
        return hypot(p.x - (a.x + t * vx), p.y - (a.y + t * vy))
    }

    /// All `style="…"` attribute values in a piece of SVG text, sorted.
    func styleStrings(in text: String) -> [String] {
        var out: [String] = []
        var rest = Substring(text)
        while let r = rest.range(of: "style=\"") {
            rest = rest[r.upperBound...]
            guard let end = rest.firstIndex(of: "\"") else { break }
            out.append(String(rest[..<end]))
            rest = rest[rest.index(after: end)...]
        }
        return out.sorted()
    }
}
