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
    @State private var draggingAnchor: (path: Int, index: Int)? = nil

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

            // Anchors of the selected element.
            if let sel = selected, sel < doc.elements.count {
                for a in Editing.anchors(of: doc.elements[sel]) {
                    let v = CGPoint(x: a.position.x * t.s + t.tx, y: a.position.y * t.s + t.ty)
                    let r: CGFloat = 3.5
                    let rect = CGRect(x: v.x - r, y: v.y - r, width: 2 * r, height: 2 * r)
                    ctx.fill(Path(ellipseIn: rect), with: .color(.white))
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
                if draggingAnchor == nil {
                    // Drag start: grab an anchor of the selected element if the
                    // press is on one; otherwise this drag is a selection tap.
                    if let sel = selected, sel < doc.elements.count {
                        let hit = nearestAnchor(
                            of: doc.elements[sel], to: v.startLocation, t: t)
                        if let hit, hit.dist <= hitRadius {
                            draggingAnchor = (hit.anchor.path, hit.anchor.index)
                        }
                    }
                }
                if let d = draggingAnchor, let sel = selected {
                    model.moveAnchor(
                        element: sel, path: d.path, anchor: d.index,
                        to: docPoint(from: v.location, doc: doc, in: size))
                }
            }
            .onEnded { v in
                defer { draggingAnchor = nil }
                guard draggingAnchor == nil else { return }
                // A click (no anchor grabbed): select the element whose anchor
                // set comes closest to the click.
                guard let doc = model.document else { return }
                let t = transform(doc: doc, in: size)
                var best: (element: Int, dist: CGFloat)? = nil
                for (i, el) in doc.elements.enumerated() {
                    if let hit = nearestAnchor(of: el, to: v.location, t: t) {
                        if best == nil || hit.dist < best!.dist {
                            best = (i, hit.dist)
                        }
                    }
                }
                if let best, best.dist <= 60 {
                    selected = best.element
                } else {
                    selected = nil
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
