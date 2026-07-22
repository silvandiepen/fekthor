import Foundation

/// Number formatting for the editor's SVG writer (plan 08): corpus style —
/// at most two decimals, trailing zeros stripped, no leading zero on |v| < 1
/// ("0.5" → ".5"), never "-0". `String(format:)` without a locale argument is
/// not localised, so the decimal separator is always ".".
public enum SVGNum {
    public static func format(_ v: Double) -> String {
        var s = String(format: "%.2f", v)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        if s == "-0" || s.isEmpty { return "0" }
        if s.hasPrefix("0.") {
            s.removeFirst()
        } else if s.hasPrefix("-0.") {
            // "-0.5" → "-.5"
            s = "-" + s.dropFirst(2)
        }
        return s
    }
}

/// The full SVG 1.1 path-data grammar (plan 08, step 3): MLHVCSQTAZ upper and
/// lower case, implicit command repeats, compact numbers (".5", "5e-2",
/// "1-2"), unspaced arc flags. One `RefinedPath` per subpath.
///
/// Representation notes:
/// - Quadratics are elevated to exact cubics (the model has no quad segment);
///   T-reflection still uses the true quadratic control point.
/// - An `A` command becomes a native `.arc` when circular, and cubic spans of
///   at most 90° when elliptical (endpoint-to-centre conversion per SVG F.6).
public enum SVGPathData {
    public struct ParseError: Error, CustomStringConvertible {
        public var message: String
        public init(message: String) { self.message = message }
        public var description: String { "SVG path data: \(message)" }
    }

    public static func parse(_ d: String) throws -> [RefinedPath] {
        var parser = Parser(d)
        return try parser.run()
    }

    /// Serialise subpaths back to a `d` string. Arcs are converted to cubics
    /// by default (browser-safe, edit-ready); pass `emitArcs: true` for trace
    /// parity with `SVGExport`.
    public static func serialize(_ paths: [RefinedPath], emitArcs: Bool = false) -> String {
        var d = ""
        for original in paths {
            let rp = emitArcs ? original : Editing.cubicized(original)
            d += "M" + SVGNum.format(rp.start.x) + " " + SVGNum.format(rp.start.y)
            for seg in rp.segments {
                switch seg {
                case .line(let to):
                    d += "L" + SVGNum.format(to.x) + " " + SVGNum.format(to.y)
                case .cubic(let c1, let c2, let to):
                    d +=
                        "C" + SVGNum.format(c1.x) + " " + SVGNum.format(c1.y) + " "
                        + SVGNum.format(c2.x) + " " + SVGNum.format(c2.y) + " "
                        + SVGNum.format(to.x) + " " + SVGNum.format(to.y)
                case .arc(_, let r, let sa, let ea, let cw):
                    let sweep = PathRefine.arcSweep(sa, ea, clockwise: cw)
                    let largeArc = sweep > .pi ? 1 : 0
                    let end = seg.endPoint
                    d +=
                        "A" + SVGNum.format(r) + " " + SVGNum.format(r)
                        + " 0 \(largeArc) \(cw ? 1 : 0) "
                        + SVGNum.format(end.x) + " " + SVGNum.format(end.y)
                }
            }
            if rp.closed { d += "Z" }
        }
        return d
    }

    // MARK: - Parser

    struct Parser {
        let chars: [Character]
        var i = 0
        var out: [RefinedPath] = []
        var segments: [RefinedSegment] = []
        var subpathStart = Pt(0, 0)
        var current = Pt(0, 0)
        var open = false
        var lastCubicControl: Pt? = nil
        var lastQuadControl: Pt? = nil

        init(_ d: String) { chars = Array(d) }

        mutating func run() throws -> [RefinedPath] {
            skipSeparators()
            guard i < chars.count else { return [] }
            guard chars[i] == "M" || chars[i] == "m" else {
                throw ParseError(message: "must start with a moveto")
            }
            var command: Character = "M"
            while true {
                skipSeparators()
                guard i < chars.count else { break }
                let c = chars[i]
                if c.isLetter {
                    command = c
                    i += 1
                } else {
                    // Implicit repeat; extra moveto pairs continue as lineto.
                    if command == "M" { command = "L" }
                    if command == "m" { command = "l" }
                }
                try apply(command)
            }
            flush(closed: false)
            return out
        }

        mutating func apply(_ command: Character) throws {
            let relative = command.isLowercase
            switch command {
            case "M", "m":
                begin(at: try point(relative: relative))
            case "L", "l":
                add(.line(to: try point(relative: relative)))
            case "H", "h":
                let x = try number()
                add(.line(to: Pt(relative ? current.x + x : x, current.y)))
            case "V", "v":
                let y = try number()
                add(.line(to: Pt(current.x, relative ? current.y + y : y)))
            case "C", "c":
                let c1 = try point(relative: relative)
                let c2 = try point(relative: relative)
                let to = try point(relative: relative)
                addCubic(c1: c1, c2: c2, to: to)
            case "S", "s":
                let c1 = reflect(lastCubicControl)
                let c2 = try point(relative: relative)
                let to = try point(relative: relative)
                addCubic(c1: c1, c2: c2, to: to)
            case "Q", "q":
                let qc = try point(relative: relative)
                let to = try point(relative: relative)
                addQuad(qc: qc, to: to)
            case "T", "t":
                let qc = reflect(lastQuadControl)
                let to = try point(relative: relative)
                addQuad(qc: qc, to: to)
            case "A", "a":
                let rx = try number()
                let ry = try number()
                let rot = try number()
                let largeArc = try flag()
                let sweep = try flag()
                let to = try point(relative: relative)
                let segs = SVGPathData.arcSegments(
                    from: current, rx: rx, ry: ry, rotationDeg: rot,
                    largeArc: largeArc, sweep: sweep, to: to)
                for seg in segs { add(seg) }
                // A degenerate arc (from == to) emits nothing; keep position.
                current = to
                lastCubicControl = nil
                lastQuadControl = nil
            case "Z", "z":
                let sp = subpathStart
                flush(closed: true)
                // The pen returns to the subpath start; a following non-M
                // command begins a new subpath there (add() opens it lazily).
                current = sp
                subpathStart = sp
                lastCubicControl = nil
                lastQuadControl = nil
            default:
                throw ParseError(message: "unknown command '\(command)'")
            }
        }

        // MARK: Subpath assembly

        mutating func begin(at p: Pt) {
            flush(closed: false)
            subpathStart = p
            current = p
            segments = []
            open = true
            lastCubicControl = nil
            lastQuadControl = nil
        }

        mutating func flush(closed: Bool) {
            guard open else { return }
            out.append(RefinedPath(start: subpathStart, segments: segments, closed: closed))
            segments = []
            open = false
        }

        mutating func add(_ seg: RefinedSegment) {
            if !open {
                open = true
                subpathStart = current
                segments = []
            }
            segments.append(seg)
            current = seg.endPoint
            lastCubicControl = nil
            lastQuadControl = nil
        }

        mutating func addCubic(c1: Pt, c2: Pt, to: Pt) {
            add(.cubic(c1: c1, c2: c2, to: to))
            lastCubicControl = c2
        }

        mutating func addQuad(qc: Pt, to: Pt) {
            // Exact degree elevation: C1 = P0 + 2/3(QC-P0), C2 = P1 + 2/3(QC-P1).
            let c1 = Pt(current.x + 2.0 / 3.0 * (qc.x - current.x),
                        current.y + 2.0 / 3.0 * (qc.y - current.y))
            let c2 = Pt(to.x + 2.0 / 3.0 * (qc.x - to.x),
                        to.y + 2.0 / 3.0 * (qc.y - to.y))
            add(.cubic(c1: c1, c2: c2, to: to))
            lastQuadControl = qc
        }

        func reflect(_ control: Pt?) -> Pt {
            guard let c = control else { return current }
            return Pt(2 * current.x - c.x, 2 * current.y - c.y)
        }

        // MARK: Tokens

        mutating func skipSeparators() {
            while i < chars.count {
                let c = chars[i]
                if c == " " || c == "," || c == "\n" || c == "\t" || c == "\r" {
                    i += 1
                } else {
                    break
                }
            }
        }

        mutating func point(relative: Bool) throws -> Pt {
            let x = try number()
            let y = try number()
            return relative ? Pt(current.x + x, current.y + y) : Pt(x, y)
        }

        mutating func number() throws -> Double {
            skipSeparators()
            var s = ""
            if i < chars.count, chars[i] == "+" || chars[i] == "-" {
                s.append(chars[i])
                i += 1
            }
            while i < chars.count, chars[i].isNumber {
                s.append(chars[i])
                i += 1
            }
            if i < chars.count, chars[i] == "." {
                s.append(".")
                i += 1
                while i < chars.count, chars[i].isNumber {
                    s.append(chars[i])
                    i += 1
                }
            }
            if i < chars.count, chars[i] == "e" || chars[i] == "E" {
                // Only an exponent when digits (optionally signed) follow.
                var j = i + 1
                if j < chars.count, chars[j] == "+" || chars[j] == "-" { j += 1 }
                if j < chars.count, chars[j].isNumber {
                    s.append("e")
                    i += 1
                    if chars[i] == "+" || chars[i] == "-" {
                        s.append(chars[i])
                        i += 1
                    }
                    while i < chars.count, chars[i].isNumber {
                        s.append(chars[i])
                        i += 1
                    }
                }
            }
            guard let v = Double(s), v.isFinite else {
                throw ParseError(message: "expected number at index \(i)")
            }
            return v
        }

        /// Arc flags are single characters and may be unspaced ("…0 011 0").
        mutating func flag() throws -> Bool {
            skipSeparators()
            guard i < chars.count, chars[i] == "0" || chars[i] == "1" else {
                throw ParseError(message: "expected arc flag at index \(i)")
            }
            let v = chars[i] == "1"
            i += 1
            return v
        }
    }

    // MARK: - Arc conversion (SVG 1.1 appendix F.6)

    /// Convert an endpoint-parameterised arc to segments: a native `.arc`
    /// when circular, cubic spans (≤90° each) when elliptical. Degenerate
    /// arcs follow the spec: same endpoints → nothing, zero radius → line.
    static func arcSegments(
        from p0: Pt, rx rxIn: Double, ry ryIn: Double, rotationDeg: Double,
        largeArc: Bool, sweep: Bool, to p1: Pt
    ) -> [RefinedSegment] {
        if abs(p0.x - p1.x) < 1e-12 && abs(p0.y - p1.y) < 1e-12 { return [] }
        var rx = abs(rxIn)
        var ry = abs(ryIn)
        if rx < 1e-12 || ry < 1e-12 { return [.line(to: p1)] }
        let phi = rotationDeg * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)
        let dx = (p0.x - p1.x) / 2
        let dy = (p0.y - p1.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let s = sqrt(lambda)
            rx *= s
            ry *= s
        }
        let sign: Double = largeArc != sweep ? 1 : -1
        let num = max(0, rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p)
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        let coef = den > 0 ? sign * sqrt(num / den) : 0
        let cxp = coef * rx * y1p / ry
        let cyp = -coef * ry * x1p / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let dot = ux * vx + uy * vy
            let len = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
            guard len > 0 else { return 0 }
            var a = acos(max(-1, min(1, dot / len)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle(
            (x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        if abs(rx - ry) < 1e-9 {
            // Circular: the axis rotation only offsets the parameter angle.
            return [
                .arc(
                    center: Pt(cx, cy), radius: rx,
                    startAngle: theta1 + phi, endAngle: theta1 + delta + phi,
                    clockwise: delta > 0)
            ]
        }

        // Elliptical: cubic spans, tangent-matched at the chunk boundaries.
        let chunks = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / Double(chunks)
        let alpha = 4.0 / 3.0 * tan(step / 4)
        func pointAt(_ a: Double) -> Pt {
            let ex = rx * cos(a)
            let ey = ry * sin(a)
            return Pt(cx + cosPhi * ex - sinPhi * ey, cy + sinPhi * ex + cosPhi * ey)
        }
        func derivativeAt(_ a: Double) -> Pt {
            let ex = -rx * sin(a)
            let ey = ry * cos(a)
            return Pt(cosPhi * ex - sinPhi * ey, sinPhi * ex + cosPhi * ey)
        }
        var segs: [RefinedSegment] = []
        var a0 = theta1
        for k in 0..<chunks {
            let a1 = a0 + step
            let s0 = pointAt(a0)
            let s1 = pointAt(a1)
            let d0 = derivativeAt(a0)
            let d1 = derivativeAt(a1)
            // Land the final span exactly on the command's endpoint.
            let end = k == chunks - 1 ? p1 : s1
            segs.append(
                .cubic(
                    c1: Pt(s0.x + alpha * d0.x, s0.y + alpha * d0.y),
                    c2: Pt(s1.x - alpha * d1.x, s1.y - alpha * d1.y),
                    to: end))
            a0 = a1
        }
        return segs
    }
}
