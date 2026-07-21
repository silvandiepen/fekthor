import FekthorKit
import SwiftUI

/// Node editing V1: the vector document drawn live as CGPaths with draggable
/// anchor points. Click a shape to select it; drag its anchors to reshape.
/// Geometry rules (control points following, arc degrade, closed seams) live
/// engine-side in `Editing`; this view only maps screen ↔ document space.
struct EditCanvasView: View {
    @ObservedObject var model: ConversionModel
    @Binding var zoom: CGFloat
    @Binding var offset: CGSize

    @State private var selected: Int? = nil
    @State private var activeAnchor: (path: Int, index: Int)? = nil
    @State private var draggingAnchor: (path: Int, index: Int)? = nil
    @State private var draggingHandle: (segment: Int, kind: Editing.HandleKind)? = nil
    @State private var gestureBegan = false

    private let hitRadius: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Rectangle().fill(Color(nsColor: .textBackgroundColor))
                canvas(in: geo.size)
            }
            .clipped()
        }
        .frame(minWidth: 300, minHeight: 340)
    }

    private func canvas(in size: CGSize) -> some View {
        // editGeneration invalidates the canvas on every anchor move.
        let _ = model.editGeneration
        return Canvas { ctx, canvasSize in
            guard let doc = model.document else { return }
            let t = transform(doc: doc, in: canvasSize)
            var cg = CGAffineTransform.identity
            cg = cg.translatedBy(x: t.tx, y: t.ty)
            cg = cg.scaledBy(x: t.s, y: t.s)

            for element in doc.elements {
                switch element {
                case .fill(let f):
                    let path = CGPathBuilder.fillPath(f.geometry, smoothing: model.smoothing)
                    var p = Path(path)
                    p = p.applying(cg)
                    ctx.fill(p, with: .color(color(f.paint)), style: FillStyle(eoFill: true))
                case .stroke(let s):
                    let path = CGPathBuilder.strokePath(s, smoothing: model.smoothing)
                    var p = Path(path)
                    p = p.applying(cg)
                    ctx.stroke(
                        p, with: .color(rgbColor(s.color)),
                        style: StrokeStyle(
                            lineWidth: s.width * t.s, lineCap: .round, lineJoin: .round))
                }
            }

            // Anchors of the selected element; control levers of the active anchor.
            if let sel = selected, sel < doc.elements.count {
                if let active = activeAnchor {
                    for h in Editing.handles(
                        of: doc.elements[sel], path: active.path, anchor: active.index)
                    {
                        let hv = CGPoint(x: h.position.x * t.s + t.tx, y: h.position.y * t.s + t.ty)
                        let av = CGPoint(x: h.anchor.x * t.s + t.tx, y: h.anchor.y * t.s + t.ty)
                        var lever = Path()
                        lever.move(to: av)
                        lever.addLine(to: hv)
                        ctx.stroke(lever, with: .color(.blue.opacity(0.6)), lineWidth: 1)
                        let r: CGFloat = 3
                        let rect = CGRect(x: hv.x - r, y: hv.y - r, width: 2 * r, height: 2 * r)
                        var diamond = Path()
                        diamond.move(to: CGPoint(x: hv.x, y: rect.minY))
                        diamond.addLine(to: CGPoint(x: rect.maxX, y: hv.y))
                        diamond.addLine(to: CGPoint(x: hv.x, y: rect.maxY))
                        diamond.addLine(to: CGPoint(x: rect.minX, y: hv.y))
                        diamond.closeSubpath()
                        ctx.fill(diamond, with: .color(.blue))
                    }
                }
                for a in Editing.anchors(of: doc.elements[sel]) {
                    let v = CGPoint(x: a.position.x * t.s + t.tx, y: a.position.y * t.s + t.ty)
                    let isActive =
                        activeAnchor.map { $0.path == a.path && $0.index == a.index } ?? false
                    let r: CGFloat = isActive ? 4.5 : 3.5
                    let rect = CGRect(x: v.x - r, y: v.y - r, width: 2 * r, height: 2 * r)
                    ctx.fill(Path(ellipseIn: rect), with: .color(isActive ? .blue : .white))
                    ctx.stroke(Path(ellipseIn: rect), with: .color(.blue), lineWidth: 1.5)
                }
            }
        }
        .gesture(dragGesture(in: size))
    }

    // MARK: - Transform (document → view)

    private struct T {
        var s: CGFloat
        var tx: CGFloat
        var ty: CGFloat
    }

    private func transform(doc: VectorDocument, in size: CGSize) -> T {
        let W = CGFloat(doc.width)
        let H = CGFloat(doc.height)
        guard W > 0, H > 0 else { return T(s: 1, tx: 0, ty: 0) }
        let s0 = min(size.width / W, size.height / H)
        let s = s0 * zoom
        // scaledToFit centres the fitted image; scaleEffect scales about the
        // view centre; offset shifts — same maths as the preview panes.
        let tx = size.width / 2 - s * W / 2 + offset.width
        let ty = size.height / 2 - s * H / 2 + offset.height
        return T(s: s, tx: tx, ty: ty)
    }

    private func docPoint(from v: CGPoint, doc: VectorDocument, in size: CGSize) -> Pt {
        let t = transform(doc: doc, in: size)
        return Pt(Double((v.x - t.tx) / t.s), Double((v.y - t.ty) / t.s))
    }

    // MARK: - Interaction

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                guard let doc = model.document else { return }
                let t = transform(doc: doc, in: size)
                if draggingAnchor == nil, draggingHandle == nil, !gestureBegan {
                    gestureBegan = true
                    // Priority: a control handle of the active anchor, then an
                    // anchor of the selected element; otherwise a selection tap.
                    if let sel = selected, sel < doc.elements.count {
                        if let active = activeAnchor {
                            for h in Editing.handles(
                                of: doc.elements[sel], path: active.path, anchor: active.index)
                            {
                                let hv = CGPoint(
                                    x: h.position.x * t.s + t.tx, y: h.position.y * t.s + t.ty)
                                if hypot(hv.x - v.startLocation.x, hv.y - v.startLocation.y)
                                    <= hitRadius
                                {
                                    model.beginEditGesture()
                                    draggingHandle = (h.segment, h.kind)
                                    break
                                }
                            }
                        }
                        if draggingHandle == nil {
                            let hit = nearestAnchor(
                                of: doc.elements[sel], to: v.startLocation, t: t)
                            if let hit, hit.dist <= hitRadius {
                                model.beginEditGesture()
                                draggingAnchor = (hit.anchor.path, hit.anchor.index)
                                activeAnchor = (hit.anchor.path, hit.anchor.index)
                            }
                        }
                    }
                }
                let target = docPoint(from: v.location, doc: doc, in: size)
                if let h = draggingHandle, let sel = selected, let active = activeAnchor {
                    model.moveHandle(
                        element: sel, path: active.path, segment: h.segment, kind: h.kind,
                        to: target)
                } else if let d = draggingAnchor, let sel = selected {
                    model.moveAnchor(element: sel, path: d.path, anchor: d.index, to: target)
                }
            }
            .onEnded { v in
                let wasEditing = draggingAnchor != nil || draggingHandle != nil
                draggingAnchor = nil
                draggingHandle = nil
                gestureBegan = false
                guard !wasEditing else { return }
                // A click (nothing grabbed): select the element / anchor whose
                // anchor set comes closest to the click.
                guard let doc = model.document else { return }
                let t = transform(doc: doc, in: size)
                var best: (element: Int, anchor: Editing.Anchor, dist: CGFloat)? = nil
                for (i, el) in doc.elements.enumerated() {
                    if let hit = nearestAnchor(of: el, to: v.location, t: t) {
                        if best == nil || hit.dist < best!.dist {
                            best = (i, hit.anchor, hit.dist)
                        }
                    }
                }
                if let best, best.dist <= 60 {
                    selected = best.element
                    activeAnchor = best.dist <= 20 ? (best.anchor.path, best.anchor.index) : nil
                } else {
                    selected = nil
                    activeAnchor = nil
                }
                model.editGeneration += 1
            }
    }

    private func nearestAnchor(
        of element: Element, to view: CGPoint, t: T
    ) -> (anchor: Editing.Anchor, dist: CGFloat)? {
        var best: (Editing.Anchor, CGFloat)? = nil
        for a in Editing.anchors(of: element) {
            let v = CGPoint(x: a.position.x * t.s + t.tx, y: a.position.y * t.s + t.ty)
            let d = hypot(v.x - view.x, v.y - view.y)
            if best == nil || d < best!.1 { best = (a, d) }
        }
        return best.map { (anchor: $0.0, dist: $0.1) }
    }

    // MARK: - Colours

    private func color(_ paint: Paint) -> Color {
        switch paint {
        case .solid(let c): return rgbColor(c)
        case .linear(let g): return rgbColor(g.stops.first?.color ?? [0, 0, 0])
        case .radial(let g): return rgbColor(g.stops.first?.color ?? [0, 0, 0])
        }
    }

    private func rgbColor(_ c: [UInt8]) -> Color {
        Color(
            red: Double(c.count > 0 ? c[0] : 0) / 255,
            green: Double(c.count > 1 ? c[1] : 0) / 255,
            blue: Double(c.count > 2 ? c[2] : 0) / 255)
    }
}
