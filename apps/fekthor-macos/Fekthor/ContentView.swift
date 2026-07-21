import FekthorKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = ConversionModel()
    @State private var showInspector = true
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero

    var body: some View {
        NavigationStack {
            Group {
                if model.sourceImage == nil {
                    EmptyStateView(model: model)
                } else {
                    VStack(spacing: 0) {
                        ComparisonView(
                            source: model.sourceImage, vector: model.vectorImage,
                            busy: model.isBusy, zoom: $zoom, offset: $offset)
                        Divider()
                        statusBar
                    }
                }
            }
            .navigationTitle("Fekthor")
            .toolbar { toolbarContent }
            .inspector(isPresented: $showInspector) {
                InspectorView(model: model)
                    .inspectorColumnWidth(min: 250, ideal: 290, max: 380)
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { model.handleDrop($0) }
            .onPasteCommand(of: [.image, .fileURL]) { _ in model.paste() }
            .onChange(of: model.imageGeneration) { _, _ in
                zoom = 1
                offset = .zero
            }
            .onAppear { model.loadLaunchArgumentIfPresent() }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { model.openPanel() } label: { Label("Open", systemImage: "photo.badge.plus") }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if zoom != 1 || offset != .zero {
                Button {
                    zoom = 1
                    offset = .zero
                } label: { Label("Fit", systemImage: "arrow.up.left.and.arrow.down.right") }
            }
            Button { model.exportSVG() } label: {
                Label("Export SVG", systemImage: "square.and.arrow.up")
            }
            .disabled(!model.hasResult)
            Button { showInspector.toggle() } label: {
                Label("Inspector", systemImage: "sidebar.trailing")
            }
        }
    }

    private var statusBar: some View {
        HStack {
            Text(model.status).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if model.hasResult {
                Text(
                    model.mode == .strokes
                        ? String(
                            format: "quality %.0f%%  ·  strokes %d  ·  nodes %d",
                            model.overallQuality * 100, model.strokes, model.nodes)
                        : String(
                            format: "quality %.0f%%  ·  exact %.1f%%  ·  PSNR %.1f dB  ·  nodes %d",
                            model.overallQuality * 100, model.exactPct, model.psnr, model.nodes)
                )
                .font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }
}

// MARK: - Empty state

private struct EmptyStateView: View {
    @ObservedObject var model: ConversionModel

    var body: some View {
        ZStack {
            Rectangle().fill(Color(nsColor: .windowBackgroundColor))
            VStack(spacing: 16) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 52)).foregroundStyle(.tertiary)
                Text("Drop an image here").font(.title2).fontWeight(.medium)
                Text("Turn line art and flat images into editable strokes and shapes.")
                    .foregroundStyle(.secondary)
                Button { model.openPanel() } label: { Label("Open Image", systemImage: "folder") }
                    .controlSize(.large)
                    .padding(.top, 4)
                Text("or press ⌘V to paste · PNG · JPEG · TIFF · HEIC · WebP")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(40)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                    )
                    .foregroundStyle(.quaternary)
                    .padding(28)
            )
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { model.handleDrop($0) }
    }
}

// MARK: - Synchronized zoom/pan comparison

private struct ComparisonView: View {
    let source: NSImage?
    let vector: NSImage?
    let busy: Bool
    @Binding var zoom: CGFloat
    @Binding var offset: CGSize

    private func setZoom(_ z: CGFloat) { zoom = min(24, max(1, z)) }
    private func reset() {
        zoom = 1
        offset = .zero
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            HSplitView {
                pane(title: "Source", image: source, busy: false)
                pane(title: "Vector", image: vector, busy: busy)
            }
            .overlay(
                TrackpadCatcher(
                    onPan: { dx, dy in
                        offset = CGSize(width: offset.width + dx, height: offset.height + dy)
                    },
                    onZoom: { m in setZoom(zoom * (1 + m)) }
                )
            )
            zoomControls
        }
    }

    private var zoomControls: some View {
        HStack(spacing: 2) {
            Button { setZoom(zoom / 1.25) } label: { Image(systemName: "minus") }
            Text("\(Int(zoom * 100))%").font(.callout.monospacedDigit()).frame(width: 52)
            Button { setZoom(zoom * 1.25) } label: { Image(systemName: "plus") }
            Divider().frame(height: 16)
            Button { reset() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.quaternary))
        .padding(.bottom, 12)
    }

    private func pane(title: String, image: NSImage?, busy: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
            }
            .padding(8)
            GeometryReader { _ in
                ZStack {
                    Rectangle().fill(Color(nsColor: .textBackgroundColor))
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .scaleEffect(zoom)
                            .offset(offset)
                            .opacity(busy ? 0.5 : 1)
                    }
                }
                .clipped()
            }
        }
        .frame(minWidth: 300, minHeight: 340)
    }
}

/// Captures trackpad two-finger scroll (pan) and pinch (zoom) events.
private struct TrackpadCatcher: NSViewRepresentable {
    let onPan: (CGFloat, CGFloat) -> Void
    let onZoom: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = CatcherView()
        v.onPan = onPan
        v.onZoom = onZoom
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let v = nsView as? CatcherView else { return }
        v.onPan = onPan
        v.onZoom = onZoom
    }

    final class CatcherView: NSView {
        var onPan: ((CGFloat, CGFloat) -> Void)?
        var onZoom: ((CGFloat) -> Void)?
        override func scrollWheel(with event: NSEvent) {
            onPan?(event.scrollingDeltaX, event.scrollingDeltaY)
        }
        override func magnify(with event: NSEvent) {
            onZoom?(event.magnification)
        }
        // Click-drag to pan.
        override func mouseDown(with event: NSEvent) {}
        override func mouseDragged(with event: NSEvent) {
            onPan?(event.deltaX, event.deltaY)
        }
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }
        // Receive scroll/pinch over the canvas. Clicks here have no target, so
        // capturing them is harmless; toolbar/inspector/zoom controls sit above.
        override func hitTest(_ point: NSPoint) -> NSView? {
            bounds.contains(convert(point, from: superview)) ? self : nil
        }
        override var acceptsFirstResponder: Bool { true }
    }
}

// MARK: - Inspector

private struct InspectorView: View {
    @ObservedObject var model: ConversionModel

    var body: some View {
        Form {
            if model.isBusy {
                Section {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Processing…").foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            Section("Vectorise") {
                Picker("Mode", selection: $model.mode) {
                    Text("Shapes").tag(Mode.shapes)
                    Text("Strokes").tag(Mode.strokes)
                    Text("Gradient").tag(Mode.gradient)
                }
                .onChange(of: model.mode) { _, _ in model.convert() }

                if model.mode == .shapes {
                    Toggle("Logo", isOn: $model.logoPreset)
                        .onChange(of: model.logoPreset) { _, enabled in
                            if enabled {
                                model.applyLogoPreset()
                            } else {
                                model.convert()
                            }
                        }
                }

                Picker("Resolution", selection: $model.resolution) {
                    Text("Fast · 512").tag(512)
                    Text("Balanced · 1024").tag(1024)
                    Text("Detailed · 2048").tag(2048)
                }
                .onChange(of: model.resolution) { _, _ in model.resolutionChanged() }

                if model.mode == .shapes || model.mode == .gradient {
                    Toggle("Auto colours", isOn: $model.autoColors)
                        .onChange(of: model.autoColors) { _, _ in model.convert() }
                    slider(
                        model.autoColors ? "Max colours" : "Colours", value: $model.colors,
                        range: 2...32, step: 1
                    ) { "\(Int(model.colors))" }
                }
                if model.mode == .shapes || model.mode == .gradient {
                    slider(
                        model.mode == .gradient ? "Blend" : "Simplicity",
                        value: $model.simplicity, range: 0...1, step: 0.05
                    ) { String(format: "%.0f%%", model.simplicity * 100) }
                }
                if model.mode == .shapes {
                    // Flatten: collapse shade families (a beard's blonds, a face's
                    // skins) into flat colours. 0% keeps today's output exactly.
                    slider("Flatten", value: $model.flatten, range: 0...1, step: 0.05) {
                        String(format: "%.0f%%", model.flatten * 100)
                    }
                }
                if model.mode == .strokes {
                    Picker("Lines from", selection: $model.strokeSource) {
                        Text("Auto").tag(StrokeSource.auto)
                        Text("Centreline").tag(StrokeSource.centreline)
                        Text("Region edges").tag(StrokeSource.edges)
                    }
                    .onChange(of: model.strokeSource) { _, _ in model.convert() }
                    Toggle("Auto line width", isOn: $model.strokeWidthAuto)
                        .onChange(of: model.strokeWidthAuto) { _, _ in model.convert() }
                    if !model.strokeWidthAuto {
                        slider("Line width", value: $model.strokeWidth, range: 0.5...30, step: 0.5) {
                            String(format: "%.1f", model.strokeWidth)
                        }
                    } else {
                        Toggle("Uniform width", isOn: $model.uniformStrokeWidth)
                            .onChange(of: model.uniformStrokeWidth) { _, _ in model.convert() }
                    }
                    Picker("Caps", selection: $model.strokeCap) {
                        Text("Round").tag(LineCap.round)
                        Text("Butt").tag(LineCap.butt)
                        Text("Square").tag(LineCap.square)
                    }
                    .onChange(of: model.strokeCap) { _, _ in model.convert() }
                    Toggle("Taper ends", isOn: $model.taper)
                        .onChange(of: model.taper) { _, _ in model.convert() }
                    Toggle("Line colour", isOn: $model.lineColorEnabled)
                        .onChange(of: model.lineColorEnabled) { _, _ in model.convert() }
                    if model.lineColorEnabled {
                        ColorPicker("Colour", selection: $model.lineColor, supportsOpacity: false)
                            .onChange(of: model.lineColor) { _, _ in model.convert() }
                    }
                }
                slider("Detail", value: $model.detail, range: 0...1, step: 0.05) {
                    String(format: "%.0f%%", model.detail * 100)
                }
                slider("Smoothing", value: $model.smoothing, range: 0...1, step: 0.05) {
                    String(format: "%.0f%%", model.smoothing * 100)
                }
                slider("Straighten", value: $model.straighten, range: 0...1, step: 0.05) {
                    String(format: "%.0f%%", model.straighten * 100)
                }
            }

            if !model.sourceInfo.isEmpty {
                Section("Source") {
                    LabeledContent("Working size", value: model.sourceInfo)
                }
            }

            if model.hasResult {
                Section("Result") {
                    // One honest, mode-aware score comparable across all modes.
                    LabeledContent(
                        "Quality", value: String(format: "%.0f%%", model.overallQuality * 100))
                    // Pixel-match metrics only apply to fill modes; Strokes output is
                    // line art, so comparing it to a colour source is not meaningful.
                    if model.mode == .strokes {
                        LabeledContent("Strokes", value: "\(model.strokes)")
                    } else {
                        LabeledContent("Exact match", value: String(format: "%.1f%%", model.exactPct))
                        LabeledContent("PSNR", value: String(format: "%.1f dB", model.psnr))
                        LabeledContent("Fills", value: "\(model.fills)")
                    }
                    LabeledContent("Nodes", value: "\(model.nodes)")
                    LabeledContent("SVG size", value: "\(model.svgKB) KB")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func slider(
        _ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double,
        _ label: @escaping () -> String
    ) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text(label()).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step) { editing in
                if !editing { model.convert() }
            }
        }
    }
}
