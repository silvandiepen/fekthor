import Foundation

public struct SVGWriteOptions: Sendable {
    /// Emit native `A` commands for circular `.arc` segments instead of the
    /// default arc→cubic conversion (trace parity with `SVGExport`).
    public var emitArcs: Bool
    public init(emitArcs: Bool = false) {
        self.emitArcs = emitArcs
    }
}

/// `GraphicDocument` → SVG text (plan 08, step 5).
///
/// The writer is deterministic (pure function of the document) and idempotent
/// with the reader: `write(read(write(read(f)))) == write(read(f))`. Numbers
/// use the corpus style (`SVGNum`), style declarations keep their stored
/// order, primitives stay native elements, raw nodes are pasted verbatim, and
/// the XML declaration is emitted only when the source had one.
///
/// Element attributes are emitted in one canonical order — ordinary
/// attributes (source order), geometry, presentation declarations, transform,
/// `style` — which is what makes a rewrite of a rewrite byte-stable.
public enum SVGWriter {
    public static func write(
        _ doc: GraphicDocument, options: SVGWriteOptions = SVGWriteOptions()
    ) -> String {
        var s = ""
        if doc.hadXMLDeclaration {
            s += "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        }
        var rootAttributes = doc.rootAttributes
        if rootAttributes.isEmpty {
            // Programmatic documents: synthesise the minimal root.
            rootAttributes.append(SVGAttribute("xmlns", "http://www.w3.org/2000/svg"))
            if let vb = doc.viewBox {
                let value = [vb.minX, vb.minY, vb.width, vb.height]
                    .map(SVGNum.format).joined(separator: " ")
                rootAttributes.append(SVGAttribute("viewBox", value))
            }
        }
        s += "<svg" + attributeString(rootAttributes) + ">\n"
        for node in doc.nodes {
            emit(node, depth: 1, options: options, into: &s)
        }
        s += "</svg>\n"
        return s
    }

    // MARK: - Nodes

    static func emit(
        _ node: GraphicNode, depth: Int, options: SVGWriteOptions, into s: inout String
    ) {
        let pad = String(repeating: "  ", count: depth)
        switch node {
        case .raw(let raw):
            s += pad + raw.xml + "\n"
        case .group(let group):
            var open = pad + "<g"
            open += attributeString(group.attributes)
            open += presentationAttributes(group.style)
            open += transformAttribute(group.transform)
            open += styleAttribute(group.style)
            if group.children.isEmpty {
                s += open + "/>\n"
            } else {
                s += open + ">\n"
                for child in group.children {
                    emit(child, depth: depth + 1, options: options, into: &s)
                }
                s += pad + "</g>\n"
            }
        case .shape(let shape):
            var line = pad + "<" + tagName(shape.kind)
            line += attributeString(shape.attributes)
            line += geometryAttributes(shape.kind, options: options)
            line += presentationAttributes(shape.style)
            line += transformAttribute(shape.transform)
            line += styleAttribute(shape.style)
            s += line + "/>\n"
        }
    }

    // MARK: - Attributes

    static func tagName(_ kind: ShapeKind) -> String {
        switch kind {
        case .path: return "path"
        case .line: return "line"
        case .polyline: return "polyline"
        case .polygon: return "polygon"
        case .rect: return "rect"
        case .circle: return "circle"
        case .ellipse: return "ellipse"
        }
    }

    static func geometryAttributes(_ kind: ShapeKind, options: SVGWriteOptions) -> String {
        func n(_ v: Double) -> String { SVGNum.format(v) }
        switch kind {
        case .path(let paths):
            return attr("d", SVGPathData.serialize(paths, emitArcs: options.emitArcs))
        case .line(let from, let to):
            return attr("x1", n(from.x)) + attr("y1", n(from.y))
                + attr("x2", n(to.x)) + attr("y2", n(to.y))
        case .polyline(let pts), .polygon(let pts):
            let points = pts.map { n($0.x) + "," + n($0.y) }.joined(separator: " ")
            return attr("points", points)
        case .rect(let x, let y, let width, let height, let rx, let ry):
            var out = attr("x", n(x)) + attr("y", n(y))
                + attr("width", n(width)) + attr("height", n(height))
            if let rx = rx { out += attr("rx", n(rx)) }
            if let ry = ry { out += attr("ry", n(ry)) }
            return out
        case .circle(let center, let radius):
            return attr("cx", n(center.x)) + attr("cy", n(center.y)) + attr("r", n(radius))
        case .ellipse(let center, let rx, let ry):
            return attr("cx", n(center.x)) + attr("cy", n(center.y))
                + attr("rx", n(rx)) + attr("ry", n(ry))
        }
    }

    static func presentationAttributes(_ style: NodeStyle) -> String {
        var out = ""
        for declaration in style.declarations where declaration.origin == .attribute {
            out += attr(declaration.property, SVGStyle.string(from: declaration.value))
        }
        return out
    }

    static func styleAttribute(_ style: NodeStyle) -> String {
        let inline = SVGStyle.serializeInline(style.declarations)
        return inline.isEmpty ? "" : attr("style", inline)
    }

    static func transformAttribute(_ transform: Transform2D?) -> String {
        guard let t = transform else { return "" }
        return attr("transform", t.raw)
    }

    static func attributeString(_ attributes: [SVGAttribute]) -> String {
        var out = ""
        for attribute in attributes {
            out += attr(attribute.name, attribute.value)
        }
        return out
    }

    static func attr(_ name: String, _ value: String) -> String {
        " " + name + "=\"" + escapeAttribute(value) + "\""
    }

    static func escapeAttribute(_ value: String) -> String {
        var out = value.replacingOccurrences(of: "&", with: "&amp;")
        out = out.replacingOccurrences(of: "<", with: "&lt;")
        out = out.replacingOccurrences(of: ">", with: "&gt;")
        out = out.replacingOccurrences(of: "\"", with: "&quot;")
        return out
    }
}
