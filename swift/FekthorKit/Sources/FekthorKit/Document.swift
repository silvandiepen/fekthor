import Foundation

/// A conversion mode. Each reconstructs different drawing semantics.
public enum Mode: String, Codable, Sendable, CaseIterable {
    /// Flat filled shapes, no strokes (colour-region tracing).
    case shapes
    /// Centreline strokes for line art (skeleton reconstruction).
    case strokes
    /// Filled shapes with fitted gradients for shaded / 3D-style art.
    case gradient
}

/// A gradient stop: a colour at a normalised offset (0…1) along the axis.
public struct GradientStop: Sendable {
    public var color: [UInt8]
    public var offset: Double
    public init(color: RGB, offset: Double) {
        self.color = [color.r, color.g, color.b]
        self.offset = offset
    }
}

/// A linear gradient in user-space (source-pixel) coordinates.
public struct LinearGradient: Sendable {
    public var p0: Pt
    public var p1: Pt
    public var stops: [GradientStop]
    public init(p0: Pt, p1: Pt, stops: [GradientStop]) {
        self.p0 = p0
        self.p1 = p1
        self.stops = stops
    }
}

/// How a filled shape is painted.
public enum Paint: Sendable {
    case solid([UInt8])  // [r,g,b]
    case linear(LinearGradient)
}

/// How a filled shape's outline is represented. `rings` is the legacy polygonal
/// form (still used by the coloring plate and any un-refined path); the geometry
/// refinement stage (plan 02) upgrades fills to `refined` typed paths or, when a
/// whole ring truly is one, a primitive (`circle` / `ellipse` / `rect`).
public enum ShapeGeometry: Sendable {
    case rings([[Pt]])  // legacy: outer + holes, even-odd
    case refined([RefinedPath])  // ring paths after refinement (outer + holes)
    case circle(center: Pt, radius: Double)
    case ellipse(center: Pt, rx: Double, ry: Double, rotation: Double)
    case rect(center: Pt, w: Double, h: Double, rotation: Double, cornerRadius: Double)
}

/// A filled region. The outer contour is first; the rest are holes, rendered
/// with the even-odd rule.
public struct FillShape: Sendable {
    public var id: String
    public var paint: Paint
    public var geometry: ShapeGeometry
    public init(id: String, paint: Paint, geometry: ShapeGeometry) {
        self.id = id
        self.paint = paint
        self.geometry = geometry
    }
    public init(id: String, paint: Paint, rings: [[Pt]]) {
        self.init(id: id, paint: paint, geometry: .rings(rings))
    }
    /// Convenience: a solid-colour fill from legacy rings.
    public init(id: String, color: RGB, rings: [[Pt]]) {
        self.init(id: id, paint: .solid([color.r, color.g, color.b]), rings: rings)
    }
    /// Convenience: a solid-colour fill from refined geometry.
    public init(id: String, color: RGB, geometry: ShapeGeometry) {
        self.init(id: id, paint: .solid([color.r, color.g, color.b]), geometry: geometry)
    }

    /// Polygonal rings for bounding-box, area and legacy rendering. Primitives
    /// and refined paths are flattened to a dense polygon on demand.
    public var rings: [[Pt]] {
        switch geometry {
        case .rings(let r): return r
        case .refined(let paths): return paths.map { PathRefine.flatten($0) }
        case .circle(let c, let r): return [ShapeGeometry.samplePrimitiveCircle(c, r, r, 0)]
        case .ellipse(let c, let rx, let ry, let rot):
            return [ShapeGeometry.samplePrimitiveCircle(c, rx, ry, rot)]
        case .rect(let c, let w, let h, let rot, let cr):
            return [ShapeGeometry.sampleRect(c, w, h, rot, cr)]
        }
    }

    /// Geometry-aware node count for simplicity scoring: anchor points, not the
    /// dense polygon. Primitives count as their handful of defining points.
    public var nodeCount: Int {
        switch geometry {
        case .rings(let r): return r.reduce(0) { $0 + $1.count }
        case .refined(let paths): return paths.reduce(0) { $0 + $1.nodeCount }
        case .circle: return 1
        case .ellipse: return 2
        case .rect: return 4
        }
    }
}

extension ShapeGeometry {
    /// Sample an (optionally rotated) ellipse into a closed polygon.
    static func samplePrimitiveCircle(_ c: Pt, _ rx: Double, _ ry: Double, _ rot: Double) -> [Pt] {
        let n = 48
        let ca = cos(rot)
        let sa = sin(rot)
        var out: [Pt] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            let t = Double(i) / Double(n) * 2 * .pi
            let ex = rx * cos(t)
            let ey = ry * sin(t)
            out.append(Pt(c.x + ex * ca - ey * sa, c.y + ex * sa + ey * ca))
        }
        return out
    }

    /// Sample an (optionally rotated, optionally rounded) rect into a polygon.
    static func sampleRect(_ c: Pt, _ w: Double, _ h: Double, _ rot: Double, _ cr: Double) -> [Pt] {
        let hw = w / 2
        let hh = h / 2
        let r = min(cr, min(hw, hh))
        let ca = cos(rot)
        let sa = sin(rot)
        func place(_ x: Double, _ y: Double) -> Pt {
            Pt(c.x + x * ca - y * sa, c.y + x * sa + y * ca)
        }
        var out: [Pt] = []
        if r <= 0.01 {
            out = [place(-hw, -hh), place(hw, -hh), place(hw, hh), place(-hw, hh)]
            return out
        }
        // Corner arcs, 6 samples each, clockwise from top-left.
        let corners: [(Pt, Double)] = [
            (Pt(-hw + r, -hh + r), .pi),  // top-left centre, start angle
            (Pt(hw - r, -hh + r), -.pi / 2),
            (Pt(hw - r, hh - r), 0),
            (Pt(-hw + r, hh - r), .pi / 2),
        ]
        for (cc, start) in corners {
            for s in 0...6 {
                let a = start + Double(s) / 6 * (.pi / 2)
                out.append(place(cc.x + r * cos(a), cc.y + r * sin(a)))
            }
        }
        return out
    }
}

/// A stroked centreline path (constant width for the MVP; width is adjustable).
public struct StrokePath: Sendable {
    public var id: String
    public var color: [UInt8]
    public var width: Double
    public var closed: Bool
    public var points: [Pt]
    /// Refined centreline geometry (plan 02). When present, export/render use it;
    /// `points` remains as a fallback and for line-mask fidelity scoring.
    public var refined: RefinedPath?
    public init(
        id: String, color: RGB, width: Double, closed: Bool, points: [Pt],
        refined: RefinedPath? = nil
    ) {
        self.id = id
        self.color = [color.r, color.g, color.b]
        self.width = width
        self.closed = closed
        self.points = points
        self.refined = refined
    }

    /// Geometry-aware node count (anchors when refined, else polyline points).
    public var nodeCount: Int { refined?.nodeCount ?? points.count }
}

public enum Element: Sendable {
    case fill(FillShape)
    case stroke(StrokePath)
}

/// The internal vector document (subset). Richer than exported SVG.
public struct VectorDocument: Sendable {
    public var width: Int
    public var height: Int
    public var elements: [Element]
    public init(width: Int, height: Int, elements: [Element] = []) {
        self.width = width
        self.height = height
        self.elements = elements
    }

    public var fillCount: Int {
        elements.filter { if case .fill = $0 { return true } else { return false } }.count
    }
    public var strokeCount: Int {
        elements.filter { if case .stroke = $0 { return true } else { return false } }.count
    }
    public var nodeCount: Int {
        elements.reduce(0) { acc, e in
            switch e {
            case .fill(let f): return acc + f.nodeCount
            case .stroke(let s): return acc + s.nodeCount
            }
        }
    }
}

// Codable for Pt so documents can be serialised.
extension Pt: Codable {
    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        let x = try c.decode(Double.self)
        let y = try c.decode(Double.self)
        self.init(x, y)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(x)
        try c.encode(y)
    }
}
