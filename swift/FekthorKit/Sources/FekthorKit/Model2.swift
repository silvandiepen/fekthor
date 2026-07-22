import Foundation

/// Model v2 — the editable SVG document model of the editor pivot (plan 08).
///
/// Where `VectorDocument` models what the tracer *produces*, `GraphicDocument`
/// models what an SVG file *contains*: faithfully enough to read a file, edit
/// part of it, and write it back with only semantic-preserving changes (the
/// normalise-on-first-save contract, D-022). Anything Fekthor does not
/// understand is carried verbatim — raw nodes, raw style values — never
/// dropped, so an edit to one shape can never damage the rest of the file.

/// The parsed `viewBox` of an `<svg>` root. The verbatim attribute string also
/// remains in `GraphicDocument.rootAttributes`; this is the typed convenience.
public struct ViewBox: Equatable, Sendable {
    public var minX: Double
    public var minY: Double
    public var width: Double
    public var height: Double
    public init(minX: Double, minY: Double, width: Double, height: Double) {
        self.minX = minX
        self.minY = minY
        self.width = width
        self.height = height
    }
}

/// An attribute exactly as it appeared in the source, order preserved.
public struct SVGAttribute: Equatable, Sendable {
    public var name: String
    public var value: String
    public init(_ name: String, _ value: String) {
        self.name = name
        self.value = value
    }
}

/// A paint (fill / stroke / stop-color). Values are typed only when Fekthor's
/// canonical serialisation reproduces the source byte-for-byte; everything
/// else — `currentColor`, `var(--x, …)`, named colours, uppercase hex — stays
/// `.raw` verbatim so it round-trips untouched.
public enum SVGPaint: Equatable, Sendable {
    case none
    case color(UInt8, UInt8, UInt8)
    /// `url(#id)` — stores the id.
    case reference(String)
    case raw(String)
}

/// A typed style value. `.raw` is the verbatim fallback for any property or
/// value Fekthor does not model (or whose canonical form differs from the
/// source — verbatim beats normalisation until the user edits the value).
public enum StyleValue: Equatable, Sendable {
    case paint(SVGPaint)
    case number(Double, unit: String)
    case keyword(String)
    case raw(String)
}

/// Where a declaration came from. This decides both its CSS priority and
/// where the writer puts it back: presentation attribute, `style="…"`, or a
/// document `<style>` rule (kept in its raw `<style>` node and therefore
/// never re-emitted inline).
public enum StyleOrigin: Equatable, Sendable {
    case attribute
    case inlineStyle
    case stylesheet
}

public struct StyleDeclaration: Equatable, Sendable {
    public var property: String
    public var value: StyleValue
    public var origin: StyleOrigin
    public init(_ property: String, _ value: StyleValue, origin: StyleOrigin = .inlineStyle) {
        self.property = property
        self.value = value
        self.origin = origin
    }
}

/// An ordered list of style declarations. Order is document order; effective
/// lookup follows the CSS priority for SVG — presentation attribute <
/// stylesheet rule < inline `style` — with later declarations winning ties.
public struct NodeStyle: Equatable, Sendable {
    public var declarations: [StyleDeclaration]
    public init(_ declarations: [StyleDeclaration] = []) {
        self.declarations = declarations
    }

    static func rank(_ origin: StyleOrigin) -> Int {
        switch origin {
        case .attribute: return 0
        case .stylesheet: return 1
        case .inlineStyle: return 2
        }
    }

    /// The winning value for a property, or nil when it is not declared.
    public func effective(_ property: String) -> StyleValue? {
        var best: (rank: Int, value: StyleValue)? = nil
        for d in declarations where d.property == property {
            let r = Self.rank(d.origin)
            // >= keeps the later declaration on equal rank (document order).
            if best == nil || r >= best!.rank { best = (r, d.value) }
        }
        return best?.value
    }

    public var fill: SVGPaint? { paintValue("fill") }
    public var stroke: SVGPaint? { paintValue("stroke") }

    public func paintValue(_ property: String) -> SVGPaint? {
        switch effective(property) {
        case .paint(let p): return p
        case .raw(let s): return SVGPaint.raw(s)
        default: return nil
        }
    }

    /// Numeric accessor that also reads `.raw` values ("1.5px" → 1.5).
    public func numberValue(_ property: String) -> Double? {
        switch effective(property) {
        case .number(let v, _): return v
        case .raw(let s), .keyword(let s):
            var digits = ""
            for ch in s {
                if ch.isNumber || ch == "." || ch == "-" || ch == "+" || ch == "e" || ch == "E" {
                    digits.append(ch)
                } else {
                    break
                }
            }
            return Double(digits)
        default: return nil
        }
    }

    public var strokeWidth: Double? { numberValue("stroke-width") }

    /// Set a property: replaces the winning writable declaration in place, or
    /// appends an inline declaration. A stylesheet-derived value cannot be
    /// written back (the `<style>` block is preserved verbatim), so it is
    /// overridden by an inline declaration instead — which is exactly the CSS
    /// priority the reader applies.
    public mutating func set(_ property: String, _ value: StyleValue) {
        var bestIndex: Int? = nil
        var bestRank = -1
        for (i, d) in declarations.enumerated() where d.property == property {
            let r = Self.rank(d.origin)
            if r >= bestRank {
                bestRank = r
                bestIndex = i
            }
        }
        if let i = bestIndex, declarations[i].origin != .stylesheet {
            declarations[i].value = value
        } else {
            declarations.append(StyleDeclaration(property, value, origin: .inlineStyle))
        }
    }
}

/// A parsed 2×3 affine matrix (SVG order: a b c d e f, columns [a c e; b d f]).
public struct TransformMatrix: Equatable, Sendable {
    public var a: Double
    public var b: Double
    public var c: Double
    public var d: Double
    public var tx: Double
    public var ty: Double
    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }

    public static let identity = TransformMatrix(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    public func multiplied(by m: TransformMatrix) -> TransformMatrix {
        TransformMatrix(
            a: a * m.a + c * m.b,
            b: b * m.a + d * m.b,
            c: a * m.c + c * m.d,
            d: b * m.c + d * m.d,
            tx: a * m.tx + c * m.ty + tx,
            ty: b * m.tx + d * m.ty + ty)
    }

    public func apply(_ p: Pt) -> Pt {
        Pt(a * p.x + c * p.y + tx, b * p.x + d * p.y + ty)
    }
}

/// A transform kept verbatim (`raw`, what the writer emits) plus a
/// best-effort parsed matrix (nil when a function was not recognised).
public struct Transform2D: Equatable, Sendable {
    public var raw: String
    public var matrix: TransformMatrix?

    public init(raw: String) {
        self.raw = raw
        self.matrix = Transform2D.parse(raw)
    }

    public init(raw: String, matrix: TransformMatrix?) {
        self.raw = raw
        self.matrix = matrix
    }

    /// Parse an SVG transform list: matrix / translate / scale / rotate /
    /// skewX / skewY, composed left to right. Returns nil on anything else.
    public static func parse(_ raw: String) -> TransformMatrix? {
        var m = TransformMatrix.identity
        var rest = Substring(raw)
        func skipSeparators() {
            while let f = rest.first, f == " " || f == "\n" || f == "\t" || f == "\r" || f == "," {
                rest = rest.dropFirst()
            }
        }
        skipSeparators()
        while !rest.isEmpty {
            guard let open = rest.firstIndex(of: "(") else { return nil }
            let name = rest[..<open].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let close = rest[open...].firstIndex(of: ")") else { return nil }
            let argText = rest[rest.index(after: open)..<close]
            let args = argText
                .split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" || $0 == "\t" || $0 == "\r" })
                .compactMap { Double($0) }
            var f: TransformMatrix
            switch name {
            case "matrix" where args.count == 6:
                f = TransformMatrix(a: args[0], b: args[1], c: args[2], d: args[3], tx: args[4], ty: args[5])
            case "translate" where args.count == 1 || args.count == 2:
                f = TransformMatrix(a: 1, b: 0, c: 0, d: 1, tx: args[0], ty: args.count == 2 ? args[1] : 0)
            case "scale" where args.count == 1 || args.count == 2:
                f = TransformMatrix(a: args[0], b: 0, c: 0, d: args.count == 2 ? args[1] : args[0], tx: 0, ty: 0)
            case "rotate" where args.count == 1 || args.count == 3:
                let rad = args[0] * .pi / 180
                let rot = TransformMatrix(a: cos(rad), b: sin(rad), c: -sin(rad), d: cos(rad), tx: 0, ty: 0)
                if args.count == 3 {
                    let toOrigin = TransformMatrix(a: 1, b: 0, c: 0, d: 1, tx: -args[1], ty: -args[2])
                    let back = TransformMatrix(a: 1, b: 0, c: 0, d: 1, tx: args[1], ty: args[2])
                    f = back.multiplied(by: rot).multiplied(by: toOrigin)
                } else {
                    f = rot
                }
            case "skewX" where args.count == 1:
                f = TransformMatrix(a: 1, b: 0, c: tan(args[0] * .pi / 180), d: 1, tx: 0, ty: 0)
            case "skewY" where args.count == 1:
                f = TransformMatrix(a: 1, b: tan(args[0] * .pi / 180), c: 0, d: 1, tx: 0, ty: 0)
            default:
                return nil
            }
            m = m.multiplied(by: f)
            rest = rest[rest.index(after: close)...]
            skipSeparators()
        }
        return m
    }
}

/// The geometry of a shape element. Primitives stay primitives so a `<rect>`
/// round-trips as a `<rect>`; they expand to `.path` only when the user edits
/// their anchors (plan 08, step 7).
public enum ShapeKind: Equatable, Sendable {
    case path([RefinedPath])
    case line(from: Pt, to: Pt)
    case polyline([Pt])
    case polygon([Pt])
    case rect(x: Double, y: Double, width: Double, height: Double, rx: Double?, ry: Double?)
    case circle(center: Pt, radius: Double)
    case ellipse(center: Pt, rx: Double, ry: Double)
}

public struct ShapeNode: Equatable, Sendable {
    public var kind: ShapeKind
    public var style: NodeStyle
    /// Attributes that are neither geometry, style, nor transform (`id`,
    /// `class`, `data-*`, …), in source order.
    public var attributes: [SVGAttribute]
    public var transform: Transform2D?
    public init(
        kind: ShapeKind, style: NodeStyle = NodeStyle(),
        attributes: [SVGAttribute] = [], transform: Transform2D? = nil
    ) {
        self.kind = kind
        self.style = style
        self.attributes = attributes
        self.transform = transform
    }
}

public struct GroupNode: Equatable, Sendable {
    public var style: NodeStyle
    public var attributes: [SVGAttribute]
    public var transform: Transform2D?
    public var children: [GraphicNode]
    public init(
        style: NodeStyle = NodeStyle(), attributes: [SVGAttribute] = [],
        transform: Transform2D? = nil, children: [GraphicNode] = []
    ) {
        self.style = style
        self.attributes = attributes
        self.transform = transform
        self.children = children
    }
}

/// Verbatim passthrough for anything Fekthor does not model — `defs`,
/// `style`, `clipPath`, comments, unknown elements. Never inspected beyond
/// the class resolver, never dropped, re-emitted exactly as stored.
public struct RawNode: Equatable, Sendable {
    public var xml: String
    public init(xml: String) {
        self.xml = xml
    }
}

public enum GraphicNode: Equatable, Sendable {
    case shape(ShapeNode)
    case group(GroupNode)
    case raw(RawNode)
}

/// An SVG document as read from (or destined for) a file.
public struct GraphicDocument: Equatable, Sendable {
    public var viewBox: ViewBox?
    /// Every `<svg>` root attribute verbatim, in source order (including
    /// xmlns, width/height and viewBox). The writer re-emits these as-is; when
    /// empty (programmatic documents) the writer synthesises xmlns + viewBox.
    public var rootAttributes: [SVGAttribute]
    public var hadXMLDeclaration: Bool
    public var nodes: [GraphicNode]
    public init(
        viewBox: ViewBox? = nil, rootAttributes: [SVGAttribute] = [],
        hadXMLDeclaration: Bool = false, nodes: [GraphicNode] = []
    ) {
        self.viewBox = viewBox
        self.rootAttributes = rootAttributes
        self.hadXMLDeclaration = hadXMLDeclaration
        self.nodes = nodes
    }
}
