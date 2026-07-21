import XCTest

@testable import FekthorKit

final class EditingTests: XCTestCase {
    func testMoveLineAnchorKeepsNeighbours() {
        let rp = RefinedPath(
            start: Pt(0, 0),
            segments: [.line(to: Pt(10, 0)), .line(to: Pt(20, 0))], closed: false)
        let el = Element.stroke(
            StrokePath(
                id: "s", color: (0, 0, 0), width: 2, closed: false,
                points: [Pt(0, 0), Pt(10, 0), Pt(20, 0)], refined: rp))
        let moved = Editing.move(el, path: 0, anchor: 1, to: Pt(10, 5))
        guard case .stroke(let s) = moved, let r = s.refined else { return XCTFail() 
    func testHandlesAndMoveHandle() {
        let rp = RefinedPath(
            start: Pt(0, 0),
            segments: [
                .cubic(c1: Pt(3, 0), c2: Pt(7, 0), to: Pt(10, 0)),
                .cubic(c1: Pt(13, 0), c2: Pt(17, 0), to: Pt(20, 0)),
            ], closed: false)
        let el = Element.stroke(
            StrokePath(
                id: "s", color: (0, 0, 0), width: 2, closed: false,
                points: [Pt(0, 0), Pt(10, 0), Pt(20, 0)], refined: rp))
        // Interior anchor: incoming c2 and outgoing c1.
        let hs = Editing.handles(of: el, path: 0, anchor: 1)
        XCTAssertEqual(hs.count, 2)
        XCTAssertEqual(hs[0].position.x, 7, accuracy: 1e-9)
        XCTAssertEqual(hs[1].position.x, 13, accuracy: 1e-9)
        // Start anchor of an open path: only the outgoing c1.
        XCTAssertEqual(Editing.handles(of: el, path: 0, anchor: 0).count, 1)
        // Move the outgoing handle; only that control changes.
        let moved = Editing.moveHandle(el, path: 0, segment: 1, kind: .c1, to: Pt(13, 6))
        guard case .stroke(let s2) = moved, let r2 = s2.refined,
            case .cubic(let c1, let c2, let end) = r2.segments[1]
        else { return XCTFail() }
        XCTAssertEqual(c1.y, 6, accuracy: 1e-9)
        XCTAssertEqual(c2.y, 0, accuracy: 1e-9)
        XCTAssertEqual(end.y, 0, accuracy: 1e-9)
    }
}
        XCTAssertEqual(r.segments[0].endPoint.y, 5, accuracy: 1e-9)
        XCTAssertEqual(r.start.x, 0, accuracy: 1e-9)
        XCTAssertEqual(r.segments[1].endPoint.x, 20, accuracy: 1e-9)
    
    func testHandlesAndMoveHandle() {
        let rp = RefinedPath(
            start: Pt(0, 0),
            segments: [
                .cubic(c1: Pt(3, 0), c2: Pt(7, 0), to: Pt(10, 0)),
                .cubic(c1: Pt(13, 0), c2: Pt(17, 0), to: Pt(20, 0)),
            ], closed: false)
        let el = Element.stroke(
            StrokePath(
                id: "s", color: (0, 0, 0), width: 2, closed: false,
                points: [Pt(0, 0), Pt(10, 0), Pt(20, 0)], refined: rp))
        // Interior anchor: incoming c2 and outgoing c1.
        let hs = Editing.handles(of: el, path: 0, anchor: 1)
        XCTAssertEqual(hs.count, 2)
        XCTAssertEqual(hs[0].position.x, 7, accuracy: 1e-9)
        XCTAssertEqual(hs[1].position.x, 13, accuracy: 1e-9)
        // Start anchor of an open path: only the outgoing c1.
        XCTAssertEqual(Editing.handles(of: el, path: 0, anchor: 0).count, 1)
        // Move the outgoing handle; only that control changes.
        let moved = Editing.moveHandle(el, path: 0, segment: 1, kind: .c1, to: Pt(13, 6))
        guard case .stroke(let s2) = moved, let r2 = s2.refined,
            case .cubic(let c1, let c2, let end) = r2.segments[1]
        else { return XCTFail() }
        XCTAssertEqual(c1.y, 6, accuracy: 1e-9)
        XCTAssertEqual(c2.y, 0, accuracy: 1e-9)
        XCTAssertEqual(end.y, 0, accuracy: 1e-9)
    }
}

    func testMoveCubicAnchorDragsAdjacentControls() {
        let rp = RefinedPath(
            start: Pt(0, 0),
            segments: [
                .cubic(c1: Pt(3, 0), c2: Pt(7, 0), to: Pt(10, 0)),
                .cubic(c1: Pt(13, 0), c2: Pt(17, 0), to: Pt(20, 0)),
            ], closed: false)
        var path = Editing.cubicized(rp)
        path = Editing.movedPath(path, anchor: 1, to: Pt(10, 4))
        guard case .cubic(_, let c2a, let endA) = path.segments[0],
            case .cubic(let c1b, _, _) = path.segments[1]
        else { return XCTFail() 
    func testHandlesAndMoveHandle() {
        let rp = RefinedPath(
            start: Pt(0, 0),
            segments: [
                .cubic(c1: Pt(3, 0), c2: Pt(7, 0), to: Pt(10, 0)),
                .cubic(c1: Pt(13, 0), c2: Pt(17, 0), to: Pt(20, 0)),
            ], closed: false)
        let el = Element.stroke(
            StrokePath(
                id: "s", color: (0, 0, 0), width: 2, closed: false,
                points: [Pt(0, 0), Pt(10, 0), Pt(20, 0)], refined: rp))
        // Interior anchor: incoming c2 and outgoing c1.
        let hs = Editing.handles(of: el, path: 0, anchor: 1)
        XCTAssertEqual(hs.count, 2)
        XCTAssertEqual(hs[0].position.x, 7, accuracy: 1e-9)
        XCTAssertEqual(hs[1].position.x, 13, accuracy: 1e-9)
        // Start anchor of an open path: only the outgoing c1.
        XCTAssertEqual(Editing.handles(of: el, path: 0, anchor: 0).count, 1)
        // Move the outgoing handle; only that control changes.
        let moved = Editing.moveHandle(el, path: 0, segment: 1, kind: .c1, to: Pt(13, 6))
        guard case .stroke(let s2) = moved, let r2 = s2.refined,
            case .cubic(let c1, let c2, let end) = r2.segments[1]
        else { return XCTFail() }
        XCTAssertEqual(c1.y, 6, accuracy: 1e-9)
        XCTAssertEqual(c2.y, 0, accuracy: 1e-9)
        XCTAssertEqual(end.y, 0, accuracy: 1e-9)
    }
}
        XCTAssertEqual(endA.y, 4, accuracy: 1e-9)
        XCTAssertEqual(c2a.y, 4, accuracy: 1e-9)  // incoming control follows
        XCTAssertEqual(c1b.y, 4, accuracy: 1e-9)  // outgoing control follows
    
    func testHandlesAndMoveHandle() {
        let rp = RefinedPath(
            start: Pt(0, 0),
            segments: [
                .cubic(c1: Pt(3, 0), c2: Pt(7, 0), to: Pt(10, 0)),
                .cubic(c1: Pt(13, 0), c2: Pt(17, 0), to: Pt(20, 0)),
            ], closed: false)
        let el = Element.stroke(
            StrokePath(
                id: "s", color: (0, 0, 0), width: 2, closed: false,
                points: [Pt(0, 0), Pt(10, 0), Pt(20, 0)], refined: rp))
        // Interior anchor: incoming c2 and outgoing c1.
        let hs = Editing.handles(of: el, path: 0, anchor: 1)
        XCTAssertEqual(hs.count, 2)
        XCTAssertEqual(hs[0].position.x, 7, accuracy: 1e-9)
        XCTAssertEqual(hs[1].position.x, 13, accuracy: 1e-9)
        // Start anchor of an open path: only the outgoing c1.
        XCTAssertEqual(Editing.handles(of: el, path: 0, anchor: 0).count, 1)
        // Move the outgoing handle; only that control changes.
        let moved = Editing.moveHandle(el, path: 0, segment: 1, kind: .c1, to: Pt(13, 6))
        guard case .stroke(let s2) = moved, let r2 = s2.refined,
            case .cubic(let c1, let c2, let end) = r2.segments[1]
        else { return XCTFail() }
        XCTAssertEqual(c1.y, 6, accuracy: 1e-9)
        XCTAssertEqual(c2.y, 0, accuracy: 1e-9)
        XCTAssertEqual(end.y, 0, accuracy: 1e-9)
    }
}

    func testCubicizedArcStaysOnCircle() {
        let rp = RefinedPath(
            start: Pt(10, 0),
            segments: [
                .arc(center: Pt(0, 0), radius: 10, startAngle: 0, endAngle: .pi, clockwise: true)
            ], closed: false)
        let cubed = Editing.cubicized(rp)
        XCTAssertFalse(
            cubed.segments.contains { if case .arc = $0 { return true } else { return false } })
        // Sample the flattened result: every point within 0.1px of the circle.
        let pts = PathRefine.flatten(cubed)
        for p in pts {
            let r = (p.x * p.x + p.y * p.y).squareRoot()
            XCTAssertEqual(r, 10, accuracy: 0.1)
        
    func testHandlesAndMoveHandle() {
        let rp = RefinedPath(
            start: Pt(0, 0),
            segments: [
                .cubic(c1: Pt(3, 0), c2: Pt(7, 0), to: Pt(10, 0)),
                .cubic(c1: Pt(13, 0), c2: Pt(17, 0), to: Pt(20, 0)),
            ], closed: false)
        let el = Element.stroke(
            StrokePath(
                id: "s", color: (0, 0, 0), width: 2, closed: false,
                points: [Pt(0, 0), Pt(10, 0), Pt(20, 0)], refined: rp))
        // Interior anchor: incoming c2 and outgoing c1.
        let hs = Editing.handles(of: el, path: 0, anchor: 1)
        XCTAssertEqual(hs.count, 2)
        XCTAssertEqual(hs[0].position.x, 7, accuracy: 1e-9)
        XCTAssertEqual(hs[1].position.x, 13, accuracy: 1e-9)
        // Start anchor of an open path: only the outgoing c1.
        XCTAssertEqual(Editing.handles(of: el, path: 0, anchor: 0).count, 1)
        // Move the outgoing handle; only that control changes.
        let moved = Editing.moveHandle(el, path: 0, segment: 1, kind: .c1, to: Pt(13, 6))
        guard case .stroke(let s2) = moved, let r2 = s2.refined,
            case .cubic(let c1, let c2, let end) = r2.segments[1]
        else { return XCTFail() }
        XCTAssertEqual(c1.y, 6, accuracy: 1e-9)
        XCTAssertEqual(c2.y, 0, accuracy: 1e-9)
        XCTAssertEqual(end.y, 0, accuracy: 1e-9)
    }
}
        XCTAssertEqual(cubed.segments.last!.endPoint.x, -10, accuracy: 0.05)
        XCTAssertEqual(cubed.segments.last!.endPoint.y, 0, accuracy: 0.05)
    
    func testHandlesAndMoveHandle() {
        let rp = RefinedPath(
            start: Pt(0, 0),
            segments: [
                .cubic(c1: Pt(3, 0), c2: Pt(7, 0), to: Pt(10, 0)),
                .cubic(c1: Pt(13, 0), c2: Pt(17, 0), to: Pt(20, 0)),
            ], closed: false)
        let el = Element.stroke(
            StrokePath(
                id: "s", color: (0, 0, 0), width: 2, closed: false,
                points: [Pt(0, 0), Pt(10, 0), Pt(20, 0)], refined: rp))
        // Interior anchor: incoming c2 and outgoing c1.
        let hs = Editing.handles(of: el, path: 0, anchor: 1)
        XCTAssertEqual(hs.count, 2)
        XCTAssertEqual(hs[0].position.x, 7, accuracy: 1e-9)
        XCTAssertEqual(hs[1].position.x, 13, accuracy: 1e-9)
        // Start anchor of an open path: only the outgoing c1.
        XCTAssertEqual(Editing.handles(of: el, path: 0, anchor: 0).count, 1)
        // Move the outgoing handle; only that control changes.
        let moved = Editing.moveHandle(el, path: 0, segment: 1, kind: .c1, to: Pt(13, 6))
        guard case .stroke(let s2) = moved, let r2 = s2.refined,
            case .cubic(let c1, let c2, let end) = r2.segments[1]
        else { return XCTFail() }
        XCTAssertEqual(c1.y, 6, accuracy: 1e-9)
        XCTAssertEqual(c2.y, 0, accuracy: 1e-9)
        XCTAssertEqual(end.y, 0, accuracy: 1e-9)
    }
}

    func testClosedPathSeamIsOneAnchor() {
        let rp = RefinedPath(
            start: Pt(0, 0),
            segments: [
                .line(to: Pt(10, 0)), .line(to: Pt(10, 10)), .line(to: Pt(0, 0)),
            ], closed: true)
        let el = Element.fill(
            FillShape(id: "f", color: (0, 0, 0), geometry: .refined([rp])))
        let anchors = Editing.anchors(of: el)
        XCTAssertEqual(anchors.count, 3)  // seam deduped
        // Moving the start also moves the closing segment's end.
        let moved = Editing.move(el, path: 0, anchor: 0, to: Pt(2, 1))
        guard case .fill(let f) = moved, case .refined(let paths) = f.geometry else {
            return XCTFail()
        
    func testHandlesAndMoveHandle() {
        let rp = RefinedPath(
            start: Pt(0, 0),
            segments: [
                .cubic(c1: Pt(3, 0), c2: Pt(7, 0), to: Pt(10, 0)),
                .cubic(c1: Pt(13, 0), c2: Pt(17, 0), to: Pt(20, 0)),
            ], closed: false)
        let el = Element.stroke(
            StrokePath(
                id: "s", color: (0, 0, 0), width: 2, closed: false,
                points: [Pt(0, 0), Pt(10, 0), Pt(20, 0)], refined: rp))
        // Interior anchor: incoming c2 and outgoing c1.
        let hs = Editing.handles(of: el, path: 0, anchor: 1)
        XCTAssertEqual(hs.count, 2)
        XCTAssertEqual(hs[0].position.x, 7, accuracy: 1e-9)
        XCTAssertEqual(hs[1].position.x, 13, accuracy: 1e-9)
        // Start anchor of an open path: only the outgoing c1.
        XCTAssertEqual(Editing.handles(of: el, path: 0, anchor: 0).count, 1)
        // Move the outgoing handle; only that control changes.
        let moved = Editing.moveHandle(el, path: 0, segment: 1, kind: .c1, to: Pt(13, 6))
        guard case .stroke(let s2) = moved, let r2 = s2.refined,
            case .cubic(let c1, let c2, let end) = r2.segments[1]
        else { return XCTFail() }
        XCTAssertEqual(c1.y, 6, accuracy: 1e-9)
        XCTAssertEqual(c2.y, 0, accuracy: 1e-9)
        XCTAssertEqual(end.y, 0, accuracy: 1e-9)
    }
}
        XCTAssertEqual(paths[0].start.x, 2, accuracy: 1e-9)
        XCTAssertEqual(paths[0].segments.last!.endPoint.x, 2, accuracy: 1e-9)
        XCTAssertEqual(paths[0].segments.last!.endPoint.y, 1, accuracy: 1e-9)
    
    func testHandlesAndMoveHandle() {
        let rp = RefinedPath(
            start: Pt(0, 0),
            segments: [
                .cubic(c1: Pt(3, 0), c2: Pt(7, 0), to: Pt(10, 0)),
                .cubic(c1: Pt(13, 0), c2: Pt(17, 0), to: Pt(20, 0)),
            ], closed: false)
        let el = Element.stroke(
            StrokePath(
                id: "s", color: (0, 0, 0), width: 2, closed: false,
                points: [Pt(0, 0), Pt(10, 0), Pt(20, 0)], refined: rp))
        // Interior anchor: incoming c2 and outgoing c1.
        let hs = Editing.handles(of: el, path: 0, anchor: 1)
        XCTAssertEqual(hs.count, 2)
        XCTAssertEqual(hs[0].position.x, 7, accuracy: 1e-9)
        XCTAssertEqual(hs[1].position.x, 13, accuracy: 1e-9)
        // Start anchor of an open path: only the outgoing c1.
        XCTAssertEqual(Editing.handles(of: el, path: 0, anchor: 0).count, 1)
        // Move the outgoing handle; only that control changes.
        let moved = Editing.moveHandle(el, path: 0, segment: 1, kind: .c1, to: Pt(13, 6))
        guard case .stroke(let s2) = moved, let r2 = s2.refined,
            case .cubic(let c1, let c2, let end) = r2.segments[1]
        else { return XCTFail() }
        XCTAssertEqual(c1.y, 6, accuracy: 1e-9)
        XCTAssertEqual(c2.y, 0, accuracy: 1e-9)
        XCTAssertEqual(end.y, 0, accuracy: 1e-9)
    }
}

    func testHandlesAndMoveHandle() {
        let rp = RefinedPath(
            start: Pt(0, 0),
            segments: [
                .cubic(c1: Pt(3, 0), c2: Pt(7, 0), to: Pt(10, 0)),
                .cubic(c1: Pt(13, 0), c2: Pt(17, 0), to: Pt(20, 0)),
            ], closed: false)
        let el = Element.stroke(
            StrokePath(
                id: "s", color: (0, 0, 0), width: 2, closed: false,
                points: [Pt(0, 0), Pt(10, 0), Pt(20, 0)], refined: rp))
        // Interior anchor: incoming c2 and outgoing c1.
        let hs = Editing.handles(of: el, path: 0, anchor: 1)
        XCTAssertEqual(hs.count, 2)
        XCTAssertEqual(hs[0].position.x, 7, accuracy: 1e-9)
        XCTAssertEqual(hs[1].position.x, 13, accuracy: 1e-9)
        // Start anchor of an open path: only the outgoing c1.
        XCTAssertEqual(Editing.handles(of: el, path: 0, anchor: 0).count, 1)
        // Move the outgoing handle; only that control changes.
        let moved = Editing.moveHandle(el, path: 0, segment: 1, kind: .c1, to: Pt(13, 6))
        guard case .stroke(let s2) = moved, let r2 = s2.refined,
            case .cubic(let c1, let c2, let end) = r2.segments[1]
        else { return XCTFail() }
        XCTAssertEqual(c1.y, 6, accuracy: 1e-9)
        XCTAssertEqual(c2.y, 0, accuracy: 1e-9)
        XCTAssertEqual(end.y, 0, accuracy: 1e-9)
    }
}
