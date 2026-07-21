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
                    model.controlsMode == .strokes
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
    @State private var mode: CompareMode = .split
    @State private var overlayOpacity: Double = 0.5
    @State private var wipe: CGFloat = 0.5

    enum CompareMode: String, CaseIterable {
        case split = "Split"
        case overlay = "Overlay"
        case wipe = "Wipe"
    }

    private func setZoom(_ z: CGFloat) { zoom = min(24, max(1, z)) }
    private func reset() {
        zoom = 1
        offset = .zero
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Group {
                    switch mode {
                    case .split:
                        HSplitView {
                            pane(title: "Source", image: source, busy: false)
                            pane(title: "Vector", image: vector, busy: busy)
                        }
                    case .overlay:
                        singleCanvas { size in
                            ZStack {
                                imageLayer(source, in: size)
                                imageLayer(vector, in: size)
                                    .opacity(overlayOpacity)
                                    .opacity(busy ? 0.5 : 1)
                            }
                        }
                    case .wipe:
                        singleCanvas { size in
                            ZStack {
                                imageLayer(source, in: size)
                                imageLayer(vector, in: size)
                                    .opacity(busy ? 0.5 : 1)
                                    .mask(alignment: .leading) {
                                        Rectangle()
                                            .frame(width: max(0, size.width * wipe))
                                    }
                            }
                        }
                    }
                }
                .overlay(
                    TrackpadCatcher(
                        onPan: { dx, dy in
                            offset = CGSize(width: offset.width + dx, height: offset.height + dy)
                        },
                        onZoom: { m in setZoom(zoom * (1 + m)) },
                        onDoubleClick: { p in zoomIn(at: p, in: geo.size) }
                    )
                )
                if mode == .wipe {
                    wipeDivider(in: geo.size)
                }
                zoomControls
            }
        }
    }

    /// Double-click: zoom in one step, anchored at the clicked point (mapped to
    /// its pane — panes share the transform, so they stay in lockstep).
    private func zoomIn(at p: CGPoint, in size: CGSize) {
        let localX: CGFloat
        let paneW: CGFloat
        if mode == .split {
            paneW = size.width / 2
            localX = p.x >= paneW ? p.x - paneW : p.x
        } else {
            paneW = size.width
            localX = p.x
        }
        let click = CGSize(width: localX - paneW / 2, height: p.y - size.height / 2)
        let newZoom = min(24, zoom * 1.6)
        let k = newZoom / zoom
        offset = CGSize(
            width: click.width - (click.width - offset.width) * k,
            height: click.height - (click.height - offset.height) * k)
        zoom = newZoom
    }

    /// The draggable wipe divider sits ABOVE the trackpad catcher so its drag
    /// wins over click-drag panning.
    private func wipeDivider(in size: CGSize) -> some View {
        let x = size.width * wipe
        return ZStack {
            Rectangle().fill(.white).frame(width: 2)
                .shadow(color: .black.opacity(0.5), radius: 2)
            Image(systemName: "arrow.left.and.right.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.black, .white)
        }
        .frame(width: 24)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .position(x: x, y: size.height / 2)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    wipe = min(0.99, max(0.01, v.location.x / size.width))
                }
        )
    }

    private func singleCanvas(@ViewBuilder content: @escaping (CGSize) -> some View) -> some View
    {
        VStack(spacing: 0) {
            HStack {
                Text(mode == .overlay ? "Overlay" : "Wipe").font(.headline)
                Spacer()
                if mode == .overlay {
                    Slider(value: $overlayOpacity, in: 0...1)
                        .frame(width: 140)
                        .controlSize(.small)
                }
            }
            .padding(8)
            GeometryReader { inner in
                ZStack {
                    Rectangle().fill(Color(nsColor: .textBackgroundColor))
                    content(inner.size)
                }
                .clipped()
            }
        }
        .frame(minWidth: 300, minHeight: 340)
    }

    @ViewBuilder
    private func imageLayer(_ image: NSImage?, in size: CGSize) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .scaleEffect(zoom)
                .offset(offset)
                .frame(width: size.width, height: size.height)
        }
    }

    private var zoomControls: some View {
        HStack(spacing: 2) {
            Picker("", selection: $mode) {
                ForEach(CompareMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            Divider().frame(height: 16)
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
    var onDoubleClick: ((CGPoint) -> Void)? = nil

    func makeNSView(context: Context) -> NSView {
        let v = CatcherView()
        v.onPan = onPan
        v.onZoom = onZoom
        v.onDoubleClick = onDoubleClick
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let v = nsView as? CatcherView else { return }
        v.onPan = onPan
        v.onZoom = onZoom
        v.onDoubleClick = onDoubleClick
    }

    final class CatcherView: NSView {
        var onPan: ((CGFloat, CGFloat) -> Void)?
        var onZoom: ((CGFloat) -> Void)?
        var onDoubleClick: ((CGPoint) -> Void)?
        override func scrollWheel(with event: NSEvent) {
            onPan?(event.scrollingDeltaX, event.scrollingDeltaY)
        }
        override func magnify(with event: NSEvent) {
            onZoom?(event.magnification)
        }
        // Click-drag to pan; double-click zooms in at the clicked point.
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                let p = convert(event.locationInWindow, from: nil)
                // NSView is bottom-left origin; SwiftUI expects top-left (y down).
                onDoubleClick?(CGPoint(x: p.x, y: bounds.height - p.y))
            }
        }
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
                    Text("Auto").tag(Mode.auto)
                    Text("Shapes").tag(Mode.shapes)
                    Text("Strokes").tag(Mode.strokes)
                    Text("Gradient").tag(Mode.gradient)
                }
                .onChange(of: model.mode) { _, _ in model.convert() }

                if model.mode == .auto {
                    LabeledContent("Detected", value: model.resolvedMode.rawValue.capitalized)
                }

                if model.controlsMode == .shapes {
                    Toggle("Logo", isOn: $model.logoPreset)
                        .onChange(of: model.logoPreset) { _, enabled in
                            if enabled {
                                model.applyLogoPreset()
                            } else {
                                model.convert()
                            }
                        }
                }

                if model.sourceIsSmall {
                    if model.enhanceAvailable {
                        Toggle("Enhance small image (AI)", isOn: $model.enhance)
                            .onChange(of: model.enhance) { _, _ in model.enhanceChanged() }
                            .help(
                                "Upscale 4x with on-device Real-ESRGAN before vectorising — small logos and icons trace far better. Fully local."
                            )
                    } else {
                        LabeledContent("Enhance small image (AI)") {
                            Button(model.modelDownloading ? "Downloading…" : "Get model (33 MB)") {
                                model.downloadEnhanceModel()
                            }
                            .disabled(model.modelDownloading)
                        }
                        .help("Downloads the Real-ESRGAN model once from models-data.hakobs.com; it runs fully on-device.")
                    }
                }
                Picker("Resolution", selection: $model.resolution) {
                    Text("Auto").tag(0)
                    Text("Fast · 512").tag(512)
                    Text("Balanced · 1024").tag(1024)
                    Text("Detailed · 2048").tag(2048)
                }
                .onChange(of: model.resolution) { _, _ in model.resolutionChanged() }

                if model.controlsMode == .shapes || model.controlsMode == .gradient {
                    Toggle("Auto colours", isOn: $model.autoColors)
                        .onChange(of: model.autoColors) { _, _ in model.convert() }
                    slider(
                        model.autoColors ? "Max colours" : "Colours", value: $model.colors,
                        range: 2...32, step: 1
                    ) { "\(Int(model.colors))" }
                }
                if model.controlsMode == .shapes || model.controlsMode == .gradient {
                    slider(
                        model.controlsMode == .gradient ? "Blend" : "Simplicity",
                        value: $model.simplicity, range: 0...1, step: 0.05
                    ) { String(format: "%.0f%%", model.simplicity * 100) }
                }
                if model.controlsMode == .shapes {
                    // Flatten: collapse shade families (a beard's blonds, a face's
                    // skins) into flat colours. 0% keeps today's output exactly.
                    slider("Flatten", value: $model.flatten, range: 0...1, step: 0.05) {
                        String(format: "%.0f%%", model.flatten * 100)
                    }
                    Toggle("Part aware (AI)", isOn: $model.partAware)
                        .onChange(of: model.partAware) { _, _ in model.convert() }
                        .help(
                            "Use on-device Vision segmentation so regions never merge across a detected part boundary. Fully local."
                        )
                }
                if model.controlsMode == .strokes {
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
                    if model.controlsMode == .strokes {
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
