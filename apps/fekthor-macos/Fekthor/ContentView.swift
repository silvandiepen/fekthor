import FekthorKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = ConversionModel()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            Divider()
            HSplitView {
                ImagePane(title: "Source", image: model.sourceImage, busy: false)
                ImagePane(title: "Vector", image: model.vectorImage, busy: model.isBusy)
            }
            Divider()
            HStack {
                Text(model.status)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(model.metrics)
                    .font(.system(.callout, design: .monospaced))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            model.handleDrop(providers)
        }
        .onAppear { model.loadLaunchArgumentIfPresent() }
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            Button {
                model.openPanel()
            } label: {
                Label("Open", systemImage: "photo.badge.plus")
            }

            Divider().frame(height: 20)

            Picker("Mode", selection: $model.mode) {
                Text("Shapes").tag(Mode.shapes)
                Text("Strokes").tag(Mode.strokes)
                Text("Gradient").tag(Mode.gradient)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .onChange(of: model.mode) { _, _ in model.convert() }

            if model.mode == .shapes || model.mode == .gradient {
                HStack(spacing: 6) {
                    Text("Colors").foregroundStyle(.secondary)
                    Slider(value: $model.colors, in: 2...32, step: 1) { editing in
                        if !editing { model.convert() }
                    }
                    .frame(width: 120)
                    Text("\(Int(model.colors))").monospacedDigit().frame(width: 22)
                }
            }

            HStack(spacing: 6) {
                Text("Detail").foregroundStyle(.secondary)
                Slider(value: $model.epsilon, in: 0.25...4, step: 0.25) { editing in
                    if !editing { model.convert() }
                }
                .frame(width: 100)
            }

            Spacer()

            if model.isBusy {
                ProgressView().controlSize(.small)
            }

            Button {
                model.exportSVG()
            } label: {
                Label("Export SVG", systemImage: "square.and.arrow.up")
            }
            .disabled(model.vectorImage == nil)
        }
    }
}

/// A titled image pane with a soft checkerboard-style backdrop.
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
