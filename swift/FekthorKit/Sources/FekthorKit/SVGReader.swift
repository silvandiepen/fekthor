import Foundation

public enum SVGReadError: Error, CustomStringConvertible {
    case notAnSVG
    case malformed(String)
    public var description: String {
        switch self {
        case .notAnSVG: return "SVG reader: root element is not <svg>"
        case .malformed(let m): return "SVG reader: \(m)"
        }
    }
}

/// SVG file → `GraphicDocument` (plan 08, step 4).
///
/// Foundation's `XMLDocument` does the XML work; this reader types only the
/// elements Fekthor edits (`path`, the primitives, `g`) and carries everything
/// else — `defs`, `style`, `clipPath`, comments, unknown elements, and any
/// shape whose geometry fails to parse — as verbatim raw nodes. A file is
/// therefore never damaged by being opened and saved: what the editor does
/// not understand, it does not touch.
///
/// Attribute order inside an element is not semantically significant in SVG;
/// the writer emits a canonical order, which is what makes
/// read → write → read stable (the normalise-on-first-save contract).
public enum SVGReader {
    static let shapeElements: Set<String> = [
        "path", "line", "polyline", "polygon", "rect", "circle", "ellipse",
    ]

    public static func read(_ text: String) throws -> GraphicDocument {
        guard let data = text.data(using: .utf8) else {
            throw SVGReadError.malformed("text is not encodable as UTF-8")
        }
        return try read(data: data, sourceText: text)
    }

    public static func read(_ data: Data) throws -> GraphicDocument {
        try read(data: data, sourceText: String(data: data, encoding: .utf8) ?? "")
    }

    static func read(data: Data, sourceText: String) throws -> GraphicDocument {
        let xml: XMLDocument
        do {
            xml = try XMLDocument(
                data: data, options: [.nodePreserveWhitespace, .nodePreserveCDATA])
        } catch {
            throw SVGReadError.malformed("\(error)")
        }
        guard let root = xml.rootElement(), elementName(root) == "svg" else {
            throw SVGReadError.notAnSVG
        }
        let hadDeclaration = sourceText
            .drop(while: { $0 == "\u{FEFF}" || $0.isWhitespace })
            .hasPrefix("<?xml")
        let rootAttributes = rootAttributeList(root)
        var viewBox: ViewBox? = nil
        if let vb = rootAttributes.first(where: { $0.name == "viewBox" }) {
            let parts = vb.value
                .split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" || $0 == "\t" || $0 == "\r" })
                .compactMap { Double($0) }
            if parts.count == 4 {
                viewBox = ViewBox(minX: parts[0], minY: parts[1], width: parts[2], height: parts[3])
            }
        }
        // Resolve document <style> class rules once for the whole tree. The
        // <style> nodes themselves stay verbatim raw nodes; these declarations
        // only feed effective-style lookups and are never re-emitted inline.
        var classMap: [String: [StyleDeclaration]] = [:]
        collectStylesheets(root, into: &classMap)

        var nodes: [GraphicNode] = []
        for child in root.children ?? [] {
            if let node = convert(child, classMap: classMap) { nodes.append(node) }
        }
        return GraphicDocument(
            viewBox: viewBox, rootAttributes: rootAttributes,
            hadXMLDeclaration: hadDeclaration, nodes: nodes)
    }

    // MARK: - Tree conversion

    static func convert(_ node: XMLNode, classMap: [String: [StyleDeclaration]]) -> GraphicNode? {
        switch node.kind {
        case .element:
            guard let element = node as? XMLElement else {
                return .raw(RawNode(xml: node.xmlString))
            }
            let name = elementName(element)
            if shapeElements.contains(name) {
                if let shape = try? convertShape(element, name: name, classMap: classMap) {
                    return .shape(shape)
                }
                // Unparseable geometry: carry the element verbatim instead of
                // guessing — fidelity beats coverage.
                return .raw(RawNode(xml: node.xmlString))
            }
            if name == "g" {
                let parts = styleAndAttributes(element, geometryNames: [], classMap: classMap)
                var children: [GraphicNode] = []
                for child in element.children ?? [] {
                    if let c = convert(child, classMap: classMap) { children.append(c) }
                }
                return .group(
                    GroupNode(
                        style: parts.style, attributes: parts.attributes,
                        transform: parts.transform, children: children))
            }
            return .raw(RawNode(xml: node.xmlString))
        case .text:
            let text = node.stringValue ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
            return .raw(RawNode(xml: node.xmlString))
        default:
            return .raw(RawNode(xml: node.xmlString))
        }
    }

    struct ElementParts {
        var style: NodeStyle
        var attributes: [SVGAttribute]
        var transform: Transform2D?
    }

    static func styleAndAttributes(
        _ element: XMLElement, geometryNames: Set<String>,
        classMap: [String: [StyleDeclaration]]
    ) -> ElementParts {
        var declarations: [StyleDeclaration] = []
        var leftovers: [SVGAttribute] = []
        var transform: Transform2D? = nil
        for attr in attributeList(element) {
            if geometryNames.contains(attr.name) { continue }
            if attr.name == "transform" {
                transform = Transform2D(raw: attr.value)
                continue
            }
            if attr.name == "style" {
                declarations += SVGStyle.parseDeclarations(attr.value, origin: .inlineStyle)
                continue
            }
            if SVGStyle.presentationProperties.contains(attr.name) {
                declarations.append(
                    StyleDeclaration(
                        attr.name, SVGStyle.value(property: attr.name, string: attr.value),
                        origin: .attribute))
                continue
            }
            if attr.name == "class" {
                leftovers.append(attr)
                for token in attr.value.split(separator: " ") {
                    if let rule = classMap[String(token)] { declarations += rule }
                }
                continue
            }
            leftovers.append(attr)
        }
        return ElementParts(
            style: NodeStyle(declarations), attributes: leftovers, transform: transform)
    }

    struct GeometryError: Error {}

    static func convertShape(
        _ element: XMLElement, name: String, classMap: [String: [StyleDeclaration]]
    ) throws -> ShapeNode {
        let kind: ShapeKind
        let geometryNames: Set<String>
        switch name {
        case "path":
            geometryNames = ["d"]
            guard let d = element.attribute(forName: "d")?.stringValue else {
                throw GeometryError()
            }
            kind = .path(try SVGPathData.parse(d))
        case "line":
            geometryNames = ["x1", "y1", "x2", "y2"]
            kind = .line(
                from: Pt(try number(element, "x1"), try number(element, "y1")),
                to: Pt(try number(element, "x2"), try number(element, "y2")))
        case "polyline", "polygon":
            geometryNames = ["points"]
            guard let points = element.attribute(forName: "points")?.stringValue else {
                throw GeometryError()
            }
            let values = points
                .split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" || $0 == "\t" || $0 == "\r" })
                .map { Double($0) }
            let doubles = values.compactMap { $0 }
            guard doubles.count == values.count, doubles.count % 2 == 0, doubles.count >= 2
            else { throw GeometryError() }
            var pts: [Pt] = []
            var i = 0
            while i < doubles.count {
                pts.append(Pt(doubles[i], doubles[i + 1]))
                i += 2
            }
            kind = name == "polygon" ? .polygon(pts) : .polyline(pts)
        case "rect":
            geometryNames = ["x", "y", "width", "height", "rx", "ry"]
            kind = .rect(
                x: try number(element, "x"), y: try number(element, "y"),
                width: try number(element, "width"), height: try number(element, "height"),
                rx: try optionalNumber(element, "rx"), ry: try optionalNumber(element, "ry"))
        case "circle":
            geometryNames = ["cx", "cy", "r"]
            kind = .circle(
                center: Pt(try number(element, "cx"), try number(element, "cy")),
                radius: try number(element, "r"))
        case "ellipse":
            geometryNames = ["cx", "cy", "rx", "ry"]
            kind = .ellipse(
                center: Pt(try number(element, "cx"), try number(element, "cy")),
                rx: try number(element, "rx"), ry: try number(element, "ry"))
        default:
            throw GeometryError()
        }
        let parts = styleAndAttributes(element, geometryNames: geometryNames, classMap: classMap)
        return ShapeNode(
            kind: kind, style: parts.style, attributes: parts.attributes,
            transform: parts.transform)
    }

    /// A numeric geometry attribute; missing means the SVG default of 0.
    static func number(_ element: XMLElement, _ name: String) throws -> Double {
        guard let text = element.attribute(forName: name)?.stringValue else { return 0 }
        guard let v = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), v.isFinite
        else { throw GeometryError() }
        return v
    }

    static func optionalNumber(_ element: XMLElement, _ name: String) throws -> Double? {
        guard let text = element.attribute(forName: name)?.stringValue else { return nil }
        guard let v = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), v.isFinite
        else { throw GeometryError() }
        return v
    }

    // MARK: - Helpers

    static func elementName(_ node: XMLNode) -> String {
        let n = node.name ?? ""
        if let colon = n.lastIndex(of: ":") {
            return String(n[n.index(after: colon)...])
        }
        return n
    }

    static func attributeList(_ element: XMLElement) -> [SVGAttribute] {
        (element.attributes ?? []).map {
            SVGAttribute($0.name ?? "", $0.stringValue ?? "")
        }
    }

    /// XMLDocument surfaces `xmlns`/`xmlns:*` declarations as namespace nodes,
    /// not attributes — merge them back in (namespaces first, canonically) so
    /// the written root keeps the declarations browsers require.
    static func rootAttributeList(_ element: XMLElement) -> [SVGAttribute] {
        var out: [SVGAttribute] = []
        for ns in element.namespaces ?? [] {
            let prefix = ns.name ?? ""
            let name = prefix.isEmpty ? "xmlns" : "xmlns:" + prefix
            out.append(SVGAttribute(name, ns.stringValue ?? ""))
        }
        // Guard against platforms that also list xmlns among the attributes.
        out += attributeList(element).filter { attr in
            !attr.name.hasPrefix("xmlns") || !out.contains(where: { $0.name == attr.name })
        }
        return out
    }

    static func collectStylesheets(
        _ element: XMLElement, into map: inout [String: [StyleDeclaration]]
    ) {
        if elementName(element) == "style" {
            for (name, declarations) in SVGStyle.parseStylesheet(element.stringValue ?? "") {
                map[name, default: []] += declarations
            }
            return
        }
        for child in element.children ?? [] {
            if let el = child as? XMLElement { collectStylesheets(el, into: &map) }
        }
    }
}
