import Foundation

/// Semantic SVG export. Filled paths keep `fill`/`fill-rule`; stroked paths keep
/// real `stroke` attributes (never expanded to outlines). Refined geometry emits
/// `L`/`A`/`C`; recognised whole shapes emit real `<circle>`/`<ellipse>`/`<rect>`.
/// Precision is applied only at export. The geometry emitted here is the exact
/// geometry the CoreGraphics preview renders (shared `RefinedPath`), so
/// preview == export.
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

    /// Path data for a legacy polygonal ring (Catmull-Rom fallback).
    static func ringPath(_ ring: [Pt], smoothing: Double) -> String {
        let (start, segs) = PathBuilder.closed(ring, strength: smoothing)
        var d = "M" + num(start.x) + " " + num(start.y) + " "
        for s in segs {
            d +=
                "C" + num(s.c1.x) + " " + num(s.c1.y) + " " + num(s.c2.x) + " " + num(s.c2.y)
                + " " + num(s.end.x) + " " + num(s.end.y) + " "
        }
        d += "Z"
        return d
    }

    /// Path data for a refined path (M / L / A / C … [Z]).
    static func refinedPath(_ rp: RefinedPath) -> String {
        var d = "M" + num(rp.start.x) + " " + num(rp.start.y) + " "
        for seg in rp.segments {
            switch seg {
            case .line(let to):
                d += "L" + num(to.x) + " " + num(to.y) + " "
            case .arc(_, let r, let sa, let ea, let cw):
                let sweep = PathRefine.arcSweep(sa, ea, clockwise: cw)
                let largeArc = sweep > .pi ? 1 : 0
                // `clockwise` means increasing atan2 angle = SVG positive sweep dir.
                let sweepFlag = cw ? 1 : 0
                let end = seg.endPoint
                d +=
                    "A" + num(r) + " " + num(r) + " 0 " + "\(largeArc) \(sweepFlag) "
                    + num(end.x) + " " + num(end.y) + " "
            case .cubic(let c1, let c2, let to):
                d +=
                    "C" + num(c1.x) + " " + num(c1.y) + " " + num(c2.x) + " " + num(c2.y) + " "
                    + num(to.x) + " " + num(to.y) + " "
            }
        }
        if rp.closed { d += "Z" }
        return d
    }

    /// The SVG element for a fill's geometry (a `<path>`, or a primitive element).
    /// `attrs` carries the id + paint attributes.
    static func fillElement(_ geometry: ShapeGeometry, smoothing: Double, id: String, fill: String)
        -> String
    {
        switch geometry {
        case .rings(let rings):
            var d = ""
            for ring in rings where ring.count >= 3 { d += ringPath(ring, smoothing: smoothing) }
            return "  <path id=\"\(id)\" d=\"\(d)\" fill=\"\(fill)\" fill-rule=\"evenodd\"/>\n"
        case .refined(let paths):
            var d = ""
            for rp in paths { d += refinedPath(rp) + " " }
            return "  <path id=\"\(id)\" d=\"\(d)\" fill=\"\(fill)\" fill-rule=\"evenodd\"/>\n"
        case .circle(let c, let r):
            return
                "  <circle id=\"\(id)\" cx=\"\(num(c.x))\" cy=\"\(num(c.y))\" r=\"\(num(r))\" fill=\"\(fill)\"/>\n"
        case .ellipse(let c, let rx, let ry, let rot):
            let deg = rot * 180 / .pi
            let transform =
                abs(deg) < 0.01
                ? "" : " transform=\"rotate(\(num(deg)) \(num(c.x)) \(num(c.y)))\""
            return
                "  <ellipse id=\"\(id)\" cx=\"\(num(c.x))\" cy=\"\(num(c.y))\" rx=\"\(num(rx))\" ry=\"\(num(ry))\"\(transform) fill=\"\(fill)\"/>\n"
        case .rect(let c, let w, let h, let rot, let cr):
            let x = c.x - w / 2
            let y = c.y - h / 2
            let deg = rot * 180 / .pi
            let transform =
                abs(deg) < 0.01
                ? "" : " transform=\"rotate(\(num(deg)) \(num(c.x)) \(num(c.y)))\""
            let rxAttr = cr > 0.01 ? " rx=\"\(num(cr))\"" : ""
            return
                "  <rect id=\"\(id)\" x=\"\(num(x))\" y=\"\(num(y))\" width=\"\(num(w))\" height=\"\(num(h))\"\(rxAttr)\(transform) fill=\"\(fill)\"/>\n"
        }
    }

    public static func toSVG(_ doc: VectorDocument, smoothing: Double = 1) -> String {
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
                let fill: String
                switch f.paint {
                case .solid(let rgb): fill = hex(rgb)
                case .linear: fill = "url(#\(gradId[i] ?? "grad-0"))"
                }
                s += fillElement(f.geometry, smoothing: smoothing, id: f.id, fill: fill)
            case .stroke(let st):
                let d: String
                if let rp = st.refined {
                    d = refinedPath(rp)
                } else {
                    let (start, segs) =
                        st.closed
                        ? PathBuilder.closed(st.points, strength: smoothing)
                        : PathBuilder.open(st.points, strength: smoothing)
                    var dd = "M" + num(start.x) + " " + num(start.y) + " "
                    for s in segs {
                        dd +=
                            "C" + num(s.c1.x) + " " + num(s.c1.y) + " " + num(s.c2.x) + " "
                            + num(s.c2.y) + " " + num(s.end.x) + " " + num(s.end.y) + " "
                    }
                    if st.closed { dd += "Z" }
                    d = dd
                }
                s +=
                    "  <path id=\"\(st.id)\" d=\"\(d)\" fill=\"none\" stroke=\"\(hex(st.color))\" stroke-width=\"\(num(st.width))\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>\n"
            }
        }
        s += "</svg>\n"
        return s
    }
}
