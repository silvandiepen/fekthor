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
        var d = ""
        for (i, p) in ring.enumerated() {
            d += (i == 0 ? "M" : "L") + num(p.x) + " " + num(p.y) + " "
        }
        d += "Z"
        return d
    }

    public static func toSVG(_ doc: VectorDocument) -> String {
        var s = ""
        s +=
            "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(doc.width)\" height=\"\(doc.height)\" viewBox=\"0 0 \(doc.width) \(doc.height)\">\n"
        for el in doc.elements {
            switch el {
            case .fill(let f):
                var d = ""
                for ring in f.rings where ring.count >= 3 { d += ringPath(ring) }
                s +=
                    "  <path id=\"\(f.id)\" d=\"\(d)\" fill=\"\(hex(f.color))\" fill-rule=\"evenodd\"/>\n"
            case .stroke(let st):
                var d = ""
                for (i, p) in st.points.enumerated() {
                    d += (i == 0 ? "M" : "L") + num(p.x) + " " + num(p.y) + " "
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
