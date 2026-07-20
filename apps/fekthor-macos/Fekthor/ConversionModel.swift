import AppKit
import FekthorKit
import SwiftUI
import UniformTypeIdentifiers

/// Drives import, downscaling, conversion and preview. Engine work runs off the
/// main actor; results are published back on the main actor.
@MainActor
final class ConversionModel: ObservableObject {
    @Published var sourceImage: NSImage?
    @Published var vectorImage: NSImage?
    @Published var mode: Mode = .shapes
    @Published var autoColors: Bool = true
    @Published var colors: Double = 16
    @Published var epsilon: Double = 2.0
    @Published var simplicity: Double = 0.3
    @Published var smoothing: Double = 1.0
    @Published var strokeWidthAuto: Bool = true
    @Published var strokeWidth: Double = 4.0
    /// Working resolution (longest side). Smaller = faster, coarser.
    @Published var resolution: Int = 1024
    @Published var status: String = "Drop, open or paste an image."
    @Published var isBusy = false
    @Published var imageGeneration = 0

    // Structured result, shown in the inspector.
    @Published var hasResult = false
    @Published var exactPct: Double = 0
    @Published var psnr: Double = 0
    @Published var fills = 0
    @Published var strokes = 0
    @Published var nodes = 0
    @Published var svgKB = 0
    @Published var sourceInfo: String = ""

    /// The imported image, capped at 2048 so re-deriving working sizes is cheap.
    private var fullImage: RasterImage?
    private var originalLongest = 0
    private var workingImage: RasterImage?
    private var svg: String = ""
    private var generation = 0

    // MARK: Import

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic, .image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            load(path: url.path)
        }
    }

    func load(path: String) {
        guard let img = try? RasterImage.load(path: path) else {
            status = "Could not decode that image."
            return
        }
        adopt(img, name: (path as NSString).lastPathComponent)
    }

    func paste() {
        let pb = NSPasteboard.general
        if let nsImage = NSImage(pasteboard: pb),
            let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
            let img = try? RasterImage.from(cgImage: cg)
        {
            adopt(img, name: "Pasted image")
            return
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL], let url = urls.first {
            load(path: url.path)
            return
        }
        status = "Clipboard has no image."
    }

    private func adopt(_ img: RasterImage, name: String) {
        originalLongest = max(img.width, img.height)
        fullImage = img.scaled(maxDimension: 2048)
        imageGeneration += 1
        deriveAndConvert(name: name)
    }

    /// Re-derive the working image at the current resolution and convert.
    private func deriveAndConvert(name: String? = nil) {
        guard let full = fullImage else { return }
        let working = full.scaled(maxDimension: resolution)
        workingImage = working
        if let cg = working.cgImage() {
            sourceImage = NSImage(
                cgImage: cg, size: NSSize(width: working.width, height: working.height))
        }
        let scaleNote = originalLongest > working.width ? " (from \(originalLongest)px)" : ""
        sourceInfo = "\(working.width)×\(working.height)\(scaleNote)"
        if let name { status = "Loaded \(name)" }
        convert()
    }

    func resolutionChanged() {
        deriveAndConvert()
    }

    // MARK: Convert

    func convert() {
        guard let working = workingImage else { return }
        generation += 1
        let gen = generation
        isBusy = true
        let mode = self.mode
        let smoothing = self.smoothing
        let options = Fekthor.Options(
            colors: Int(colors), epsilon: epsilon, simplicity: simplicity, smoothing: smoothing,
            autoColors: autoColors, strokeWidth: strokeWidthAuto ? nil : strokeWidth)
        Task.detached(priority: .userInitiated) {
            do {
                let result = try Fekthor.convert(working, mode: mode, options: options)
                // Render the preview crisply (~2048px) so zooming stays sharp.
                let displayScale = max(
                    1.0, 2048.0 / Double(max(working.width, working.height)))
                let preview = Rasterizer.render(
                    result.document, smoothing: smoothing, scale: displayScale)
                let cg = preview.cgImage()
                let w = preview.width
                let h = preview.height
                let fills = result.document.fillCount
                let strokes = result.document.strokeCount
                let nodes = result.document.nodeCount
                let m = result.metrics
                let svg = result.svg
                let kb = svg.utf8.count / 1024
                await MainActor.run {
                    guard gen == self.generation else { return }
                    if let cg {
                        self.vectorImage = NSImage(cgImage: cg, size: NSSize(width: w, height: h))
                    }
                    self.svg = svg
                    self.hasResult = true
                    self.exactPct = m.exactPct
                    self.psnr = m.psnr
                    self.fills = fills
                    self.strokes = strokes
                    self.nodes = nodes
                    self.svgKB = kb
                    self.status = "Converted · \(mode.rawValue)"
                    self.isBusy = false
                }
            } catch {
                await MainActor.run {
                    guard gen == self.generation else { return }
                    self.vectorImage = nil
                    self.hasResult = false
                    self.status = "\(error)"
                    self.isBusy = false
                }
            }
        }
    }

    // MARK: Export / drop

    func exportSVG() {
        guard !svg.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "svg") ?? .xml]
        panel.nameFieldStringValue = "fekthor.svg"
        if panel.runModal() == .OK, let url = panel.url {
            try? svg.write(to: url, atomically: true, encoding: .utf8)
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

    func loadLaunchArgumentIfPresent() {
        for arg in CommandLine.arguments.dropFirst()
        where FileManager.default.fileExists(atPath: arg) {
            load(path: arg)
            return
        }
    }
}
