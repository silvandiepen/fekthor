import FekthorKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = ConversionModel()
    @State private var showInspector = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HSplitView {
                    ImagePane(title: "Source", image: model.sourceImage, busy: false)
                    ImagePane(title: "Vector", image: model.vectorImage, busy: model.isBusy)
                }
                Divider()
                HStack {
                    Text(model.status).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    if model.hasResult {
                        Text(
                            String(
                                format: "exact %.1f%%  ·  PSNR %.1f dB  ·  nodes %d",
                                model.exactPct, model.psnr, model.nodes)
                        )
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .navigationTitle("Fekthor")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        model.openPanel()
                    } label: {
                        Label("Open", systemImage: "photo.badge.plus")
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        model.exportSVG()
                    } label: {
                        Label("Export SVG", systemImage: "square.and.arrow.up")
                    }
                    .disabled(!model.hasResult)
                    Button {
                        showInspector.toggle()
                    } label: {
                        Label("Inspector", systemImage: "sidebar.trailing")
                    }
                }
            }
            .inspector(isPresented: $showInspector) {
                InspectorView(model: model)
                    .inspectorColumnWidth(min: 250, ideal: 290, max: 380)
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                model.handleDrop(providers)
            }
            .onAppear { model.loadLaunchArgumentIfPresent() }
        }
    }
}

/// The settings sidebar: vectorise controls and the result summary.
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

                if model.mode == .shapes || model.mode == .gradient {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Colors")
                            Spacer()
                            Text("\(Int(model.colors))").monospacedDigit().foregroundStyle(
                                .secondary)
                        }
                        Slider(value: $model.colors, in: 2...32, step: 1) { editing in
                            if !editing { model.convert() }
                        }
                    }
                }

                VStack(alignment: .leading) {
                    HStack {
                        Text("Detail")
                        Spacer()
                        Text(String(format: "%.2f", model.epsilon)).monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $model.epsilon, in: 0.25...4, step: 0.25) { editing in
                        if !editing { model.convert() }
                    }
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
}

/// A titled image pane with a soft backdrop.
private struct ImagePane: View {
    let title: String
    let image: NSImage?
    let busy: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
            }
            .padding(8)
            ZStack {
                Rectangle().fill(Color(nsColor: .textBackgroundColor))
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(12)
                        .opacity(busy ? 0.5 : 1)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "square.dashed")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                        Text(title == "Source" ? "Open or drop an image" : "Vector preview")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(minWidth: 320, minHeight: 360)
    }
}
