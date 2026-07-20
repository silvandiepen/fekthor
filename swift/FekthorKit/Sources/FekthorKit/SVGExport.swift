import Foundation

/// Semantic SVG export. Filled paths keep `fill`/`fill-rule`; stroked paths keep
/// real `stroke` attributes (never expanded to outlines). Precision is applied
/// only at export.
public enum SVGExport {
    static func num(_ v: Double) -> String {
        var s = String(format: "%.2f", v)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s == "-0" || s.isEmpty ? "0" : s
    }

    static func hex(_ c: [UInt8]) -> String {
        String(format: "#%02x%02x%02x", c[0], c[1], c[2])
    }

    static func ringPath(_ ring: [Pt]) -> String {
        let (start, segs) = PathBuilder.closed(ring)
        var d = "M" + num(start.x) + " " + num(start.y) + " "
        for s in segs {
            d +=
                "C" + num(s.c1.x) + " " + num(s.c1.y) + " " + num(s.c2.x) + " " + num(s.c2.y)
                + " " + num(s.end.x) + " " + num(s.end.y) + " "
        }
        d += "Z"
        return d
    }

    public static func toSVG(_ doc: VectorDocument) -> String {
        // Build gradient defs first, assigning each a stable id.
        var defs = ""
        var gradId: [Int: String] = [:]
        var gi = 0
        for (i, el) in doc.elements.enumerated() {
            if case .fill(let f) = el, case .linear(let g) = f.paint {
                let id = "grad-\(gi)"
                gradId[i] = id
                gi += 1
                defs +=
                    "    <linearGradient id=\"\(id)\" gradientUnits=\"userSpaceOnUse\" x1=\"\(num(g.p0.x))\" y1=\"\(num(g.p0.y))\" x2=\"\(num(g.p1.x))\" y2=\"\(num(g.p1.y))\">\n"
                for stop in g.stops {
                    defs +=
                        "      <stop offset=\"\(num(stop.offset))\" stop-color=\"\(hex(stop.color))\"/>\n"
                }
                defs += "    </linearGradient>\n"
            }
        }

        var s = ""
        s +=
            "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(doc.width)\" height=\"\(doc.height)\" viewBox=\"0 0 \(doc.width) \(doc.height)\">\n"
        if !defs.isEmpty { s += "  <defs>\n\(defs)  </defs>\n" }
        for (i, el) in doc.elements.enumerated() {
            switch el {
            case .fill(let f):
                var d = ""
                for ring in f.rings where ring.count >= 3 { d += ringPath(ring) }
                let fill: String
                switch f.paint {
                case .solid(let rgb): fill = hex(rgb)
                case .linear: fill = "url(#\(gradId[i] ?? "grad-0"))"
                }
                s +=
                    "  <path id=\"\(f.id)\" d=\"\(d)\" fill=\"\(fill)\" fill-rule=\"evenodd\"/>\n"
            case .stroke(let st):
                let (start, segs) =
                    st.closed ? PathBuilder.closed(st.points) : PathBuilder.open(st.points)
                var d = "M" + num(start.x) + " " + num(start.y) + " "
                for s in segs {
                    d +=
                        "C" + num(s.c1.x) + " " + num(s.c1.y) + " " + num(s.c2.x) + " "
                        + num(s.c2.y) + " " + num(s.end.x) + " " + num(s.end.y) + " "
                }
                if st.closed { d += "Z" }
                s +=
                    "  <path id=\"\(st.id)\" d=\"\(d)\" fill=\"none\" stroke=\"\(hex(st.color))\" stroke-width=\"\(num(st.width))\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>\n"
            }
        }
        s += "</svg>\n"
        return s
    }
}
