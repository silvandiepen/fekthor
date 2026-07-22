import Foundation

/// Inline-style, paint and (minimal) stylesheet parsing for Model v2 (plan
/// 08, step 3).
///
/// The typing rule is verbatim-first: a value becomes typed ONLY when its
/// canonical serialisation reproduces the source string byte-for-byte
/// (lowercase `#rrggbb`, corpus-style numbers). Everything else —
/// `currentColor`, `var(--x, …)`, named colours, uppercase hex, spaced
/// values — stays `.raw` and is re-emitted exactly as read. Reading is never
/// lossy and saving an untouched value never rewrites it.
public enum SVGStyle {
    /// Properties recognised as presentation attributes on shapes and groups.
    /// Anything else stays an ordinary attribute and round-trips untouched.
    public static let presentationProperties: Set<String> = [
        "fill", "stroke", "stroke-width", "stroke-linecap", "stroke-linejoin",
        "stroke-miterlimit", "stroke-dasharray", "stroke-dashoffset",
        "stroke-opacity", "fill-opacity", "fill-rule", "opacity", "color",
        "stop-color", "stop-opacity", "clip-rule", "paint-order",
        "vector-effect", "display", "visibility",
    ]

    static let paintProperties: Set<String> = ["fill", "stroke", "color", "stop-color"]
    static let numberProperties: Set<String> = [
        "stroke-width", "stroke-miterlimit", "stroke-dashoffset",
        "stroke-opacity", "fill-opacity", "opacity", "stop-opacity",
    ]
    static let keywordProperties: Set<String> = [
        "stroke-linecap", "stroke-linejoin", "fill-rule", "clip-rule",
        "display", "visibility", "paint-order", "vector-effect",
    ]

    // MARK: - Paints

    public static func parsePaint(_ s: String) -> SVGPaint {
        if s == "none" { return SVGPaint.none }
        if s.hasPrefix("#"), let c = hexColor(s), string(from: c) == s {
            return c
        }
        if s.hasPrefix("url(#"), s.hasSuffix(")") {
            let id = String(s.dropFirst(5).dropLast(1))
            if !id.isEmpty, !id.contains(")"), string(from: .reference(id)) == s {
                return .reference(id)
            }
        }
        return .raw(s)
    }

    static func hexColor(_ s: String) -> SVGPaint? {
        let hex = Array(s.dropFirst())
        func nibble(_ c: Character) -> UInt8? { UInt8(String(c), radix: 16) }
        if hex.count == 6 {
            guard let r1 = nibble(hex[0]), let r2 = nibble(hex[1]),
                let g1 = nibble(hex[2]), let g2 = nibble(hex[3]),
                let b1 = nibble(hex[4]), let b2 = nibble(hex[5])
            else { return nil }
            return .color(r1 << 4 | r2, g1 << 4 | g2, b1 << 4 | b2)
        }
        if hex.count == 3 {
            guard let r = nibble(hex[0]), let g = nibble(hex[1]), let b = nibble(hex[2])
            else { return nil }
            return .color(r << 4 | r, g << 4 | g, b << 4 | b)
        }
        return nil
    }

    public static func string(from paint: SVGPaint) -> String {
        switch paint {
        case .none: return "none"
        case .color(let r, let g, let b): return String(format: "#%02x%02x%02x", r, g, b)
        case .reference(let id): return "url(#\(id))"
        case .raw(let s): return s
        }
    }

    // MARK: - Values

    public static func value(property: String, string s: String) -> StyleValue {
        if paintProperties.contains(property) {
            let p = parsePaint(s)
            if case .raw = p { return .raw(s) }
            return .paint(p)
        }
        if numberProperties.contains(property) {
            let (number, unit) = splitNumberUnit(s)
            if let v = number, SVGNum.format(v) + unit == s {
                return .number(v, unit: unit)
            }
            return .raw(s)
        }
        if keywordProperties.contains(property), isKeyword(s) {
            return .keyword(s)
        }
        return .raw(s)
    }

    public static func string(from value: StyleValue) -> String {
        switch value {
        case .paint(let p): return string(from: p)
        case .number(let v, let unit): return SVGNum.format(v) + unit
        case .keyword(let k): return k
        case .raw(let s): return s
        }
    }

    static func splitNumberUnit(_ s: String) -> (Double?, String) {
        var numberPart = ""
        var rest = Substring(s)
        while let f = rest.first, f.isNumber || f == "." || f == "-" || f == "+" {
            numberPart.append(f)
            rest = rest.dropFirst()
        }
        let unit = String(rest)
        let unitOK = unit.isEmpty || unit.allSatisfy { $0.isLetter || $0 == "%" }
        guard unitOK, let v = Double(numberPart), v.isFinite else { return (nil, "") }
        return (v, unit)
    }

    static func isKeyword(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isLetter || $0 == "-" }
    }

    // MARK: - Declaration lists

    /// Parse `"stroke:#010101;stroke-width:1.5"`. Unknown properties keep
    /// their verbatim (trimmed) value.
    public static func parseDeclarations(_ css: String, origin: StyleOrigin) -> [StyleDeclaration] {
        var out: [StyleDeclaration] = []
        for chunk in css.split(separator: ";") {
            guard let colon = chunk.firstIndex(of: ":") else { continue }
            let property = chunk[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
            let valueText = chunk[chunk.index(after: colon)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !property.isEmpty else { continue }
            out.append(
                StyleDeclaration(
                    property, value(property: property, string: valueText), origin: origin))
        }
        return out
    }

    /// Serialise the `style="…"` attribute content: only inline-origin
    /// declarations, stored order, `p:v;p:v` form.
    public static func serializeInline(_ declarations: [StyleDeclaration]) -> String {
        declarations.filter { $0.origin == .inlineStyle }
            .map { "\($0.property):\(string(from: $0.value))" }
            .joined(separator: ";")
    }

    // MARK: - Minimal stylesheet (document <style> class rules)

    /// Parse only what the icon corpus needs: `.class { … }` rules (comma
    /// lists allowed). Everything else is ignored — the `<style>` block itself
    /// is preserved verbatim as a raw node, so nothing is lost.
    public static func parseStylesheet(_ css: String) -> [String: [StyleDeclaration]] {
        var text = css
        while let start = text.range(of: "/*") {
            if let end = text.range(of: "*/", range: start.upperBound..<text.endIndex) {
                text.removeSubrange(start.lowerBound..<end.upperBound)
            } else {
                text.removeSubrange(start.lowerBound..<text.endIndex)
            }
        }
        var out: [String: [StyleDeclaration]] = [:]
        for rule in text.split(separator: "}") {
            guard let brace = rule.firstIndex(of: "{") else { continue }
            let selectors = rule[..<brace].split(separator: ",")
            let body = String(rule[rule.index(after: brace)...])
            let declarations = parseDeclarations(body, origin: .stylesheet)
            guard !declarations.isEmpty else { continue }
            for selector in selectors {
                let s = selector.trimmingCharacters(in: .whitespacesAndNewlines)
                guard s.hasPrefix("."), s.count > 1 else { continue }
                let name = String(s.dropFirst())
                guard name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
                else { continue }
                out[name, default: []] += declarations
            }
        }
        return out
    }
}
