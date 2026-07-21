import Foundation

/// Node editing V1 (engine side): enumerate a document element's anchor points
/// and apply anchor moves. The app draws the anchors and feeds drags back here,
/// so the geometry rules live in one testable place.
///
/// Rules:
/// - A refined path's anchors are its start plus each segment end. Moving an
///   anchor translates the adjacent cubic control points with it, so the curve
///   keeps its shape locally instead of pinching.
/// - Arcs are parametric (centre/radius/angles) and cannot follow a free-moved
///   endpoint; a path containing arcs is degraded to cubics ONCE on its first
///   edit (visually identical within a fraction of a pixel).
/// - Primitives (circle/ellipse/rect) expose one anchor — their centre — and
///   move rigidly. Legacy rings expose every vertex.
public enum Editing {
    public struct Anchor {
        /// Which ring/path inside the element (fills can have holes).
        public var path: Int
        /// Anchor index within that path (0 = start).
        public var index: Int
        public var position: Pt
    }

    // MARK: - Anchor enumeration

    public static func anchors(of element: Element) -> [Anchor] {
        switch element {
        case .stroke(let s):
            if let rp = s.refined { return pathAnchors(rp, path: 0) }
            return s.points.enumerated().map { Anchor(path: 0, index: $0.0, position: $0.1) }
        case .fill(let f):
            switch f.geometry {
            case .refined(let paths):
                var out: [Anchor] = []
                for (pi, rp) in paths.enumerated() {
                    out.append(contentsOf: pathAnchors(rp, path: pi))
                }
                return out
            case .rings(let rings):
                var out: [Anchor] = []
                for (ri, ring) in rings.enumerated() {
                    for (i, p) in ring.enumerated() {
                        out.append(Anchor(path: ri, index: i, position: p))
                    }
                }
                return out
            case .circle(let c, _):
                return [Anchor(path: 0, index: 0, position: c)]
            case .ellipse(let c, _, _, _):
                return [Anchor(path: 0, index: 0, position: c)]
            case .rect(let c, _, _, _, _):
                return [Anchor(path: 0, index: 0, position: c)]
            }
        }
    }

    static func pathAnchors(_ rp: RefinedPath, path: Int) -> [Anchor] {
        var out = [Anchor(path: path, index: 0, position: rp.start)]
        for (i, seg) in rp.segments.enumerated() {
            out.append(Anchor(path: path, index: i + 1, position: seg.endPoint))
        }
        // A closed path's final segment usually lands back on the start; that
        // seam is ONE anchor, not two (moving the duplicate would tear the
        // loop — the start move already drags the closing segment's end).
        if rp.closed, out.count > 1 {
            let last = out[out.count - 1].position
            let dx = last.x - rp.start.x
            let dy = last.y - rp.start.y
            if dx * dx + dy * dy < 0.25 { out.removeLast() }
        }
        return out
    }

    // MARK: - Anchor moves

    /// Returns the element with the given anchor moved to `to`.
    public static func move(
        _ element: Element, path: Int, anchor: Int, to: Pt
    ) -> Element {
        switch element {
        case .stroke(var s):
            if let rp = s.refined {
                s.refined = movedPath(rp, anchor: anchor, to: to)
                // Keep the fallback polyline loosely in sync for scoring.
                s.points = PathRefine.flatten(s.refined!)
            } else if anchor < s.points.count {
                s.points[anchor] = to
            }
            return .stroke(s)
        case .fill(var f):
            switch f.geometry {
            case .refined(var paths):
                if path < paths.count {
                    paths[path] = movedPath(paths[path], anchor: anchor, to: to)
                    f.geometry = .refined(paths)
                }
            case .rings(var rings):
                if path < rings.count, anchor < rings[path].count {
                    rings[path][anchor] = to
                    f.geometry = .rings(rings)
                }
            case .circle(let c, let r):
                f.geometry = .circle(center: shifted(c, c, to), radius: r)
            case .ellipse(let c, let rx, let ry, let rot):
                f.geometry = .ellipse(center: shifted(c, c, to), rx: rx, ry: ry, rotation: rot)
            case .rect(let c, let w, let h, let rot, let cr):
                f.geometry = .rect(
                    center: shifted(c, c, to), w: w, h: h, rotation: rot, cornerRadius: cr)
            }
            return .fill(f)
        }
    }

    @inline(__always) static func shifted(_ p: Pt, _ from: Pt, _ to: Pt) -> Pt {
        Pt(p.x + (to.x - from.x), p.y + (to.y - from.y))
    }

    static func movedPath(_ rp: RefinedPath, anchor: Int, to: Pt) -> RefinedPath {
        var path = cubicized(rp)
        let n = path.segments.count
        if anchor == 0 {
            let d = (to.x - path.start.x, to.y - path.start.y)
            // Outgoing control follows the start.
            if n > 0, case .cubic(let c1, let c2, let end) = path.segments[0] {
                path.segments[0] = .cubic(
                    c1: Pt(c1.x + d.0, c1.y + d.1), c2: c2, to: end)
            }
            // On a closed path the last segment ends at the start — move that
            // end (and its incoming control) too, or the loop tears open.
            if path.closed, n > 0 {
                path.segments[n - 1] = movedEnd(path.segments[n - 1], to: to)
            }
            path.start = to
            return path
        }
        let i = anchor - 1
        guard i >= 0, i < n else { return path }
        let old = path.segments[i].endPoint
        let d = (to.x - old.x, to.y - old.y)
        path.segments[i] = movedEnd(path.segments[i], to: to)
        // The outgoing control belongs to the joint we just moved; keep it
        // attached so the curve translates locally instead of pinching.
        if i + 1 < n, case .cubic(let c1, let c2, let end) = path.segments[i + 1] {
            path.segments[i + 1] = .cubic(
                c1: Pt(c1.x + d.0, c1.y + d.1), c2: c2, to: end)
        }
        return path
    }

    static func movedEnd(_ seg: RefinedSegment, to: Pt) -> RefinedSegment {
        switch seg {
        case .line: return .line(to: to)
        case .cubic(let c1, let c2, let old):
            // Incoming control follows the endpoint.
            return .cubic(
                c1: c1, c2: Pt(c2.x + (to.x - old.x), c2.y + (to.y - old.y)), to: to)
        case .arc:
            // cubicized() removes arcs before any move; unreachable, but keep
            // the compiler total.
            return .line(to: to)
        }
    }

    // MARK: - Control handles

    public enum HandleKind: Sendable { case c1, c2 }

    /// A cubic control point adjacent to an anchor: the incoming segment's c2
    /// and/or the outgoing segment's c1.
    public struct Handle {
        public var path: Int
        /// Segment index inside the (cubicized) path.
        public var segment: Int
        public var kind: HandleKind
        public var position: Pt
        /// The anchor this handle belongs to (for drawing the lever line).
        public var anchor: Pt
    }

    /// Control handles adjacent to one anchor. Only cubic segments have
    /// handles; call after the path has been cubicized (any edit does that).
    public static func handles(
        of element: Element, path: Int, anchor: Int
    ) -> [Handle] {
        guard let rp = refinedPath(of: element, at: path) else { return [] }
        let cubed = cubicized(rp)
        let n = cubed.segments.count
        var out: [Handle] = []
        let anchorPos: Pt =
            anchor == 0
            ? cubed.start
            : (anchor - 1 < n ? cubed.segments[anchor - 1].endPoint : cubed.start)
        // Incoming segment: for anchor 0 on a closed path that's the last one.
        let incoming = anchor == 0 ? (cubed.closed ? n - 1 : -1) : anchor - 1
        if incoming >= 0, incoming < n, case .cubic(_, let c2, _) = cubed.segments[incoming] {
            out.append(
                Handle(path: path, segment: incoming, kind: .c2, position: c2, anchor: anchorPos))
        }
        let outgoing = anchor == 0 ? 0 : anchor
        if outgoing < n, case .cubic(let c1, _, _) = cubed.segments[outgoing] {
            out.append(
                Handle(path: path, segment: outgoing, kind: .c1, position: c1, anchor: anchorPos))
        }
        return out
    }

    /// Move one cubic control point. The element's path is cubicized first, so
    /// segment indices line up with what `handles(of:path:anchor:)` reported.
    public static func moveHandle(
        _ element: Element, path: Int, segment: Int, kind: HandleKind, to: Pt
    ) -> Element {
        guard let rp = refinedPath(of: element, at: path) else { return element }
        var cubed = cubicized(rp)
        guard segment < cubed.segments.count,
            case .cubic(let c1, let c2, let end) = cubed.segments[segment]
        else { return element }
        cubed.segments[segment] =
            kind == .c1 ? .cubic(c1: to, c2: c2, to: end) : .cubic(c1: c1, c2: to, to: end)
        return replacingPath(element, at: path, with: cubed)
    }

    static func refinedPath(of element: Element, at path: Int) -> RefinedPath? {
        switch element {
        case .stroke(let s): return path == 0 ? s.refined : nil
        case .fill(let f):
            if case .refined(let paths) = f.geometry, path < paths.count { return paths[path] }
            return nil
        }
    }

    static func replacingPath(_ element: Element, at path: Int, with rp: RefinedPath) -> Element {
        switch element {
        case .stroke(var s):
            if path == 0 {
                s.refined = rp
                s.points = PathRefine.flatten(rp)
            }
            return .stroke(s)
        case .fill(var f):
            if case .refined(var paths) = f.geometry, path < paths.count {
                paths[path] = rp
                f.geometry = .refined(paths)
            }
            return .fill(f)
        }
    }

    // MARK: - Arc degrade

    /// Replace every arc with cubic Bézier spans (≤90° each, k = 4/3·tan(θ/4)):
    /// the standard approximation, within ~0.03% of the true circle.
    public static func cubicized(_ rp: RefinedPath) -> RefinedPath {
        guard rp.segments.contains(where: { if case .arc = $0 { return true } else { return false } })
        else { return rp }
        var segments: [RefinedSegment] = []
        var current = rp.start
        for seg in rp.segments {
            switch seg {
            case .line, .cubic:
                segments.append(seg)
                current = seg.endPoint
            case .arc(let c, let r, let sa, let ea, let cw):
                var sweep = cw ? ea - sa : sa - ea
                while sweep < 0 { sweep += 2 * .pi }
                while sweep >= 2 * .pi { sweep -= 2 * .pi }
                let dir: Double = cw ? 1 : -1
                let chunks = max(1, Int(ceil(sweep / (.pi / 2))))
                let step = sweep / Double(chunks)
                var a0 = sa
                for _ in 0..<chunks {
                    let a1 = a0 + dir * step
                    let k = 4.0 / 3.0 * tan(step / 4)
                    let p0 = Pt(c.x + r * cos(a0), c.y + r * sin(a0))
                    let p3 = Pt(c.x + r * cos(a1), c.y + r * sin(a1))
                    // Tangents rotate with the traversal direction.
                    let t0 = Pt(-sin(a0) * dir, cos(a0) * dir)
                    let t3 = Pt(-sin(a1) * dir, cos(a1) * dir)
                    let c1 = Pt(p0.x + k * r * t0.x, p0.y + k * r * t0.y)
                    let c2 = Pt(p3.x - k * r * t3.x, p3.y - k * r * t3.y)
                    segments.append(.cubic(c1: c1, c2: c2, to: p3))
                    a0 = a1
                }
                current = segments.last!.endPoint
            }
        }
        _ = current
        return RefinedPath(start: rp.start, segments: segments, closed: rp.closed)
    }
}
