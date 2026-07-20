import AppKit
import FekthorKit
import SwiftUI
import UniformTypeIdentifiers

/// Drives import, conversion and preview. Engine work runs off the main actor;
/// results are published back on the main actor (docs/ARCHITECTURE.md coordinator).
@MainActor
final class ConversionModel: ObservableObject {
    @Published var sourceImage: NSImage?
    @Published var vectorImage: NSImage?
    @Published var mode: Mode = .shapes
    @Published var colors: Double = 16
    @Published var epsilon: Double = 1.0
    @Published var status: String = "Open or drop an image to begin."
    @Published var metrics: String = ""
    @Published var isBusy = false

    private var sourcePath: String?
    private var svg: String = ""
    private var generation = 0

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic, .image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            load(path: url.path)
        }
    }

    func load(path: String) {
        sourcePath = path
        guard let img = try? RasterImage.load(path: path), let cg = img.cgImage() else {
            status = "Could not decode that image."
            return
        }
        sourceImage = NSImage(cgImage: cg, size: NSSize(width: img.width, height: img.height))
        status = "Loaded \((path as NSString).lastPathComponent) · \(img.width)×\(img.height)"
        convert()
    }

    func convert() {
        guard let path = sourcePath else { return }
        generation += 1
        let gen = generation
        isBusy = true
        let mode = self.mode
        let options = Fekthor.Options(colors: Int(colors), epsilon: epsilon)
        Task.detached(priority: .userInitiated) {
            do {
                let img = try RasterImage.load(path: path)
                let result = try Fekthor.convert(img, mode: mode, options: options)
                let cg = result.rendered.cgImage()
                let w = result.rendered.width
                let h = result.rendered.height
                let fills = result.document.fillCount
                let strokes = result.document.strokeCount
                let nodes = result.document.nodeCount
                let m = result.metrics
                let svg = result.svg
                await MainActor.run {
                    guard gen == self.generation else { return }
                    if let cg {
                        self.vectorImage = NSImage(cgImage: cg, size: NSSize(width: w, height: h))
                    }
                    self.svg = svg
                    let semantic = mode == .strokes ? "strokes \(strokes)" : "fills \(fills)"
                    self.metrics = String(
                        format: "exact %.1f%%  ·  PSNR %.1f dB  ·  %@  ·  nodes %d",
                        m.exactPct, m.psnr, semantic, nodes)
                    self.status = "Converted · \(mode.rawValue)"
                    self.isBusy = false
                }
            } catch {
                await MainActor.run {
                    guard gen == self.generation else { return }
                    self.vectorImage = nil
                    self.metrics = ""
                    self.status = "\(error)"
                    self.isBusy = false
                }
            }
        }
    }

    func exportSVG() {
        guard !svg.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "svg") ?? .xml]
        panel.nameFieldStringValue = "fekthor.svg"
        if panel.runModal() == .OK, let url = panel.url {
            try? svg.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Load an image passed as a launch argument (used for smoke tests).
    func loadLaunchArgumentIfPresent() {
        for arg in CommandLine.arguments.dropFirst()
        where FileManager.default.fileExists(atPath: arg) {
            load(path: arg)
            return
        }
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in self.load(path: url.path) }
        }
        return true
    }
}
