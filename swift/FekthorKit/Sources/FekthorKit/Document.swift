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

/// A filled region. `rings[0]` is the outer contour; the rest are holes.
/// Rendered with the even-odd rule.
public struct FillShape: Sendable {
    public var id: String
    public var paint: Paint
    public var rings: [[Pt]]
    public init(id: String, paint: Paint, rings: [[Pt]]) {
        self.id = id
        self.paint = paint
        self.rings = rings
    }
    /// Convenience: a solid-colour fill.
    public init(id: String, color: RGB, rings: [[Pt]]) {
        self.init(id: id, paint: .solid([color.r, color.g, color.b]), rings: rings)
    }
}

/// A stroked centreline path (constant width for the MVP; width is adjustable).
public struct StrokePath: Codable, Sendable {
    public var id: String
    public var color: [UInt8]
    public var width: Double
    public var closed: Bool
    public var points: [Pt]
    public init(id: String, color: RGB, width: Double, closed: Bool, points: [Pt]) {
        self.id = id
        self.color = [color.r, color.g, color.b]
        self.width = width
        self.closed = closed
        self.points = points
    }
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
            case .fill(let f): return acc + f.rings.reduce(0) { $0 + $1.count }
            case .stroke(let s): return acc + s.points.count
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
