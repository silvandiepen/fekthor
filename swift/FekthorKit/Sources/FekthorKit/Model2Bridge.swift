import Foundation

/// One-way bridge from the tracer's `VectorDocument` to the editor's
/// `GraphicDocument` (plan 08, step 2). Lossless by construction: every
/// element becomes a shape node carrying the same geometry the SVG export
/// would emit — refined paths pass through untouched, legacy rings go through
/// the same Catmull-Rom smoothing as `SVGExport`, primitives stay primitives,
/// and gradients become a verbatim `<defs>` raw node referenced by paint.
public enum Model2Bridge {
    public static func document(from doc: VectorDocument, smoothing: Double = 1) -> GraphicDocument {
        var nodes: [GraphicNode] = []

        // Gradient defs first, with the same stable ids SVGExport assigns.
        var gradientID: [Int: String] = [:]
        var defs = ""
        var gi = 0
        for (i, element) in doc.elements.enumerated() {
            guard case .fill(let f) = element else { continue }
            switch f.paint {
            case .linear(let g):
                let id = "grad-\(gi)"
                gradientID[i] = id
                gi += 1
                defs +=
                    "<linearGradient id=\"\(id)\" gradientUnits=\"userSpaceOnUse\" x1=\"\(SVGExport.num(g.p0.x))\" y1=\"\(SVGExport.num(g.p0.y))\" x2=\"\(SVGExport.num(g.p1.x))\" y2=\"\(SVGExport.num(g.p1.y))\">"
                for stop in g.stops {
                    defs +=
                        "<stop offset=\"\(SVGExport.num(stop.offset))\" stop-color=\"\(SVGExport.hex(stop.color))\"/>"
                }
                defs += "</linearGradient>"
            case .radial(let g):
                let id = "grad-\(gi)"
                gradientID[i] = id
                gi += 1
                defs +=
                    "<radialGradient id=\"\(id)\" gradientUnits=\"userSpaceOnUse\" cx=\"\(SVGExport.num(g.center.x))\" cy=\"\(SVGExport.num(g.center.y))\" r=\"\(SVGExport.num(g.radius))\">"
                for stop in g.stops {
                    defs +=
                        "<stop offset=\"\(SVGExport.num(stop.offset))\" stop-color=\"\(SVGExport.hex(stop.color))\"/>"
                }
                defs += "</radialGradient>"
            case .solid:
                break
            }
        }
        if !defs.isEmpty {
            nodes.append(.raw(RawNode(xml: "<defs>" + defs + "</defs>")))
        }

        for (i, element) in doc.elements.enumerated() {
            switch element {
            case .fill(let f):
                nodes.append(.shape(fillShape(f, gradientID: gradientID[i], smoothing: smoothing)))
            case .stroke(let s):
                nodes.append(.shape(strokeShape(s, smoothing: smoothing)))
            }
        }

        let width = Double(doc.width)
        let height = Double(doc.height)
        return GraphicDocument(
            viewBox: ViewBox(minX: 0, minY: 0, width: width, height: height),
            rootAttributes: [
                SVGAttribute("xmlns", "http://www.w3.org/2000/svg"),
                SVGAttribute("width", "\(doc.width)"),
                SVGAttribute("height", "\(doc.height)"),
                SVGAttribute("viewBox", "0 0 \(doc.width) \(doc.height)"),
            ],
            hadXMLDeclaration: false,
            nodes: nodes)
    }

    // MARK: - Fills

    static func fillShape(_ f: FillShape, gradientID: String?, smoothing: Double) -> ShapeNode {
        let paint: SVGPaint =
            gradientID.map { SVGPaint.reference($0) } ?? solidPaint(f.paint)
        var declarations = [StyleDeclaration("fill", .paint(paint), origin: .attribute)]
        var kind: ShapeKind
        var transform: Transform2D? = nil
        switch f.geometry {
        case .refined(let paths):
            kind = .path(paths)
            declarations.append(
                StyleDeclaration("fill-rule", .keyword("evenodd"), origin: .attribute))
        case .rings(let rings):
            kind = .path(rings.filter { $0.count >= 3 }.map { ringPath($0, smoothing: smoothing) })
            declarations.append(
                StyleDeclaration("fill-rule", .keyword("evenodd"), origin: .attribute))
        case .circle(let c, let r):
            kind = .circle(center: c, radius: r)
        case .ellipse(let c, let rx, let ry, let rotation):
            kind = .ellipse(center: c, rx: rx, ry: ry)
            transform = rotationTransform(rotation, about: c)
        case .rect(let c, let w, let h, let rotation, let cornerRadius):
            kind = .rect(
                x: c.x - w / 2, y: c.y - h / 2, width: w, height: h,
                rx: cornerRadius > 0.01 ? cornerRadius : nil, ry: nil)
            transform = rotationTransform(rotation, about: c)
        }
        return ShapeNode(
            kind: kind, style: NodeStyle(declarations),
            attributes: [SVGAttribute("id", f.id)], transform: transform)
    }

    static func solidPaint(_ paint: Paint) -> SVGPaint {
        if case .solid(let rgb) = paint, rgb.count >= 3 {
            return .color(rgb[0], rgb[1], rgb[2])
        }
        return .raw("none")
    }

    static func rotationTransform(_ rotation: Double, about c: Pt) -> Transform2D? {
        let degrees = rotation * 180 / .pi
        guard abs(degrees) >= 0.01 else { return nil }
        return Transform2D(
            raw: "rotate(\(SVGExport.num(degrees)) \(SVGExport.num(c.x)) \(SVGExport.num(c.y)))")
    }

    /// A legacy polygonal ring through the same Catmull-Rom smoothing the SVG
    /// export applies, as typed cubic segments.
    static func ringPath(_ ring: [Pt], smoothing: Double) -> RefinedPath {
        let (start, segs) = PathBuilder.closed(ring, strength: smoothing)
        return RefinedPath(
            start: start,
            segments: segs.map { .cubic(c1: $0.c1, c2: $0.c2, to: $0.end) },
            closed: true)
    }

    // MARK: - Strokes

    static func strokeShape(_ s: StrokePath, smoothing: Double) -> ShapeNode {
        let path: RefinedPath
        if let refined = s.refined {
            path = refined
        } else {
            let (start, segs) =
                s.closed
                ? PathBuilder.closed(s.points, strength: smoothing)
                : PathBuilder.open(s.points, strength: smoothing)
            path = RefinedPath(
                start: start,
                segments: segs.map { .cubic(c1: $0.c1, c2: $0.c2, to: $0.end) },
                closed: s.closed)
        }
        let color: SVGPaint = s.color.count >= 3 ? .color(s.color[0], s.color[1], s.color[2]) : .raw("none")
        let declarations = [
            StyleDeclaration("fill", .paint(SVGPaint.none), origin: .attribute),
            StyleDeclaration("stroke", .paint(color), origin: .attribute),
            StyleDeclaration("stroke-width", .number(s.width, unit: ""), origin: .attribute),
            StyleDeclaration("stroke-linecap", .keyword(s.cap.rawValue), origin: .attribute),
            StyleDeclaration("stroke-linejoin", .keyword("round"), origin: .attribute),
        ]
        return ShapeNode(
            kind: .path([path]), style: NodeStyle(declarations),
            attributes: [SVGAttribute("id", s.id)])
    }
}
