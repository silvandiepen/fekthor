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
            Button { model.paste() } label: { Label("Paste", systemImage: "clipboard") }
                .keyboardShortcut("v", modifiers: .command)
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
                    String(
                        format: "exact %.1f%%  ·  PSNR %.1f dB  ·  nodes %d",
                        model.exactPct, model.psnr, model.nodes)
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
                HStack(spacing: 12) {
                    Button { model.openPanel() } label: { Label("Open Image", systemImage: "folder") }
                        .controlSize(.large)
                    Button { model.paste() } label: { Label("Paste", systemImage: "clipboard") }
                        .controlSize(.large)
                        .keyboardShortcut("v", modifiers: .command)
                }
                .padding(.top, 4)
                Text("PNG · JPEG · TIFF · HEIC · WebP")
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
    @State private var lastZoom: CGFloat = 1
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        HSplitView {
            pane(title: "Source", image: source, busy: false)
            pane(title: "Vector", image: vector, busy: busy)
        }
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
                .contentShape(Rectangle())
                .gesture(magnify.simultaneously(with: drag))
                .onTapGesture(count: 2) {
                    zoom = 1
                    offset = .zero
                    lastZoom = 1
                    lastOffset = .zero
                }
            }
        }
        .frame(minWidth: 300, minHeight: 340)
    }

    private var magnify: some Gesture {
        MagnificationGesture()
            .onChanged { v in zoom = min(24, max(1, lastZoom * v)) }
            .onEnded { _ in lastZoom = zoom }
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { v in
                offset = CGSize(
                    width: lastOffset.width + v.translation.width,
                    height: lastOffset.height + v.translation.height)
            }
            .onEnded { _ in lastOffset = offset }
    }
}

// MARK: - Inspector

private struct InspectorView: View {
    @ObservedObject var model: ConversionModel

    var body: some View {
        Form {
            Section("Vectorise") {
                Picker("Mode", selection: $model.mode) {
                    Text("Shapes").tag(Mode.shapes)
                    Text("Strokes").tag(Mode.strokes)
                    Text("Gradient").tag(Mode.gradient)
                }
                .onChange(of: model.mode) { _, _ in model.convert() }

                Picker("Resolution", selection: $model.resolution) {
                    Text("Fast · 512").tag(512)
                    Text("Balanced · 1024").tag(1024)
                    Text("Detailed · 2048").tag(2048)
                }
                .onChange(of: model.resolution) { _, _ in model.resolutionChanged() }

                if model.mode == .shapes || model.mode == .gradient {
                    slider("Colors", value: $model.colors, range: 2...32, step: 1) {
                        "\(Int(model.colors))"
                    }
                }
                slider("Detail", value: $model.epsilon, range: 0.25...4, step: 0.25) {
                    String(format: "%.2f", model.epsilon)
                }
            }

            if !model.sourceInfo.isEmpty {
                Section("Source") {
                    LabeledContent("Working size", value: model.sourceInfo)
                }
            }

            if model.hasResult {
                Section("Result") {
                    LabeledContent("Exact match", value: String(format: "%.1f%%", model.exactPct))
                    LabeledContent("PSNR", value: String(format: "%.1f dB", model.psnr))
                    if model.mode == .strokes {
                        LabeledContent("Strokes", value: "\(model.strokes)")
                    } else {
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
