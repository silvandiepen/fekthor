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
    @Published var mode: Mode = .auto
    @Published var resolvedMode: Mode = .shapes
    @Published var logoPreset: Bool = false
    @Published var autoColors: Bool = true
    @Published var autoColorMinFraction: Double = 0.004
    @Published var colors: Double = 16
    /// 0 = coarse (fewer nodes), 1 = fine (more detail). Maps to DP tolerance.
    @Published var detail: Double = 0.55
    @Published var simplicity: Double = 0.3
    /// Flatten strength (Shapes only): collapse shade families (same hue, different
    /// lightness) into flat colours. 0 = off (identical to the non-flatten pipeline).
    @Published var flatten: Double = 0
    /// ML part awareness (Vision instance masks) — Shapes only, opt-in.
    @Published var partAware: Bool = false
    /// Real-ESRGAN 4× enhancement for small sources (model optional, local).
    @Published var enhance: Bool = false
    @Published var enhanceAvailable: Bool = Enhance.isAvailable
    @Published var modelDownloading: Bool = false
    @Published var sourceIsSmall: Bool = false
    private var originalImage: RasterImage?
    @Published var smoothing: Double = 0.65
    /// Geometry-refinement straighten strength (0…1): near-straight runs collapse
    /// to single lines / axis-snapped primitives.
    @Published var straighten: Double = 0.5
    @Published var strokeWidthAuto: Bool = true
    @Published var strokeWidth: Double = 4.0
    /// Uniform width: every stroke shares the median width (per-stroke widths off).
    @Published var uniformStrokeWidth: Bool = false
    @Published var strokeSource: StrokeSource = .auto
    /// Stroke end-cap style (round/butt/square).
    @Published var strokeCap: LineCap = .round
    /// Opt-in taper: narrowing tails render as outline fills (default off).
    @Published var taper: Bool = false
    /// Line-colour override for strokes (both sources). Off = keep sampled/black.
    @Published var lineColorEnabled: Bool = false
    @Published var lineColor: Color = .black
    /// Working resolution (longest side). 0 = Auto: simple-palette images
    /// (logos, flat art) get 2048 — they are cheap and edge fidelity matters
    /// most there; everything else gets 1024.
    @Published var resolution: Int = 0
    private var simplePalette: Bool = false
    @Published var status: String = "Drop, open or paste an image."
    @Published var isBusy = false
    @Published var imageGeneration = 0

    // Structured result, shown in the inspector.
    @Published var hasResult = false
    /// Mode-aware overall quality (0…1), honest and comparable across all modes.
    @Published var overallQuality: Double = 0
    @Published var exactPct: Double = 0
    @Published var psnr: Double = 0
    @Published var fills = 0
    @Published var strokes = 0
    @Published var nodes = 0
    @Published var svgKB = 0
    @Published var sourceInfo: String = ""

    var controlsMode: Mode { mode == .auto ? resolvedMode : mode }

    /// The imported image, capped at 2048 so re-deriving working sizes is cheap.
    private var fullImage: RasterImage?
    private var originalLongest = 0
    private var workingImage: RasterImage?
    private var svg: String = ""
    private var generation = 0
    private var cachedAutoGeneration: Int?
    private var cachedAutoDetection: AutoMode.Detection?

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
        originalImage = img
        sourceIsSmall = max(img.width, img.height) <= Enhance.maxInputSide
        applySourcePipeline(name: name)
    }

    /// Original → optional ML enhancement (small sources) → capped full image.
    private func applySourcePipeline(name: String?) {
        guard let img = originalImage else { return }
        var source = img
        if enhance, sourceIsSmall, let up = Enhance.upscale4x(img) { source = up }
        // Simple-palette probe (cheap, on a thumbnail): drives Auto resolution
        // and logo auto-detection.
        let probe = ColorQuantizer.quantizeAuto(
            source.scaled(maxDimension: 256), maxColors: 6, minFraction: 0.02)
        simplePalette = probe.palette.count <= 4
        originalLongest = max(source.width, source.height)
        fullImage = source.scaled(maxDimension: 2048)
        imageGeneration += 1
        cachedAutoGeneration = nil
        cachedAutoDetection = nil
        resolvedMode = .shapes
        deriveAndConvert(name: name)
    }

    func enhanceChanged() {
        applySourcePipeline(name: nil)
    }

    /// Explicit user action (privacy plan): download the optional 4× model
    /// from the owner's R2 bucket, then enable enhancement.
    func downloadEnhanceModel() {
        guard !modelDownloading else { return }
        modelDownloading = true
        status = "Downloading Real-ESRGAN model (33 MB)…"
        Task {
            do {
                try await ModelStore.download(.realESRGAN)
                await MainActor.run {
                    self.modelDownloading = false
                    self.enhanceAvailable = Enhance.isAvailable
                    self.status = "Model installed."
                    if self.enhance { self.applySourcePipeline(name: nil) }
                }
            } catch {
                await MainActor.run {
                    self.modelDownloading = false
                    self.status = "Model download failed: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Re-derive the working image at the current resolution and convert.
    private func deriveAndConvert(name: String? = nil) {
        guard let full = fullImage else { return }
        let effectiveResolution = resolution == 0 ? (simplePalette ? 2048 : 1024) : resolution
        let working = full.scaled(maxDimension: effectiveResolution)
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
        // Higher Detail → finer curves (smaller DP tolerance).
        let eps = 4.2 - 3.9 * detail
        let lineRGB: RGB? = lineColorEnabled ? Self.rgb(from: lineColor) : nil
        let detection = mode == .auto ? resolveAutoMode(for: working) : nil
        let conversionMode = detection?.resolved ?? mode
        if let detection { resolvedMode = detection.resolved } else { resolvedMode = mode }
        // Flatten is a Shapes-only behaviour; never leak it into Strokes/Gradient or Auto
        // resolutions that are not Shapes.
        let flattenValue = conversionMode == .shapes ? flatten : 0
        // Auto + simple palette + shapes = a logo-class image: use logo-grade
        // parameters (tiny accents like an ® survive, crisper straightening)
        // without yanking the user's sliders or leaving Auto mode.
        let logoAuto = mode == .auto && conversionMode == .shapes && simplePalette
        let options = Fekthor.Options(
            colors: Int(colors), epsilon: logoAuto ? min(eps, 0.885) : eps,
            simplicity: logoAuto ? min(simplicity, 0.10) : simplicity,
            smoothing: logoAuto ? 0.35 : smoothing,
            straighten: logoAuto ? max(straighten, 0.80) : straighten,
            autoColors: autoColors,
            autoColorMinFraction: logoAuto ? 0.002 : autoColorMinFraction,
            flatten: flattenValue,
            partAware: conversionMode == .shapes && partAware,
            strokeWidth: strokeWidthAuto ? nil : strokeWidth,
            uniformStrokeWidth: uniformStrokeWidth, strokeSource: strokeSource,
            strokeCap: strokeCap, taper: taper, lineColor: lineRGB)
        let statusSuffix = logoAuto ? " · logo" : ""
        Task.detached(priority: .userInitiated) {
            do {
                let result = try Fekthor.convert(working, mode: conversionMode, options: options)
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
                let overall = result.quality.overall
                let svg = result.svg
                let kb = svg.utf8.count / 1024
                let resolvedMode = result.resolvedMode
                await MainActor.run {
                    guard gen == self.generation else { return }
                    if let cg {
                        self.vectorImage = NSImage(cgImage: cg, size: NSSize(width: w, height: h))
                    }
                    self.svg = svg
                    self.hasResult = true
                    self.overallQuality = overall
                    self.exactPct = m.exactPct
                    self.psnr = m.psnr
                    self.fills = fills
                    self.strokes = strokes
                    self.nodes = nodes
                    self.svgKB = kb
                    self.resolvedMode = resolvedMode
                    self.status =
                        mode == .auto
                        ? "Converted · auto→\(resolvedMode.rawValue)\(statusSuffix)"
                        : "Converted · \(mode.rawValue)"
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

    private func resolveAutoMode(for image: RasterImage) -> AutoMode.Detection {
        if cachedAutoGeneration == imageGeneration, let cachedAutoDetection {
            return cachedAutoDetection
        }
        let detection = AutoMode.detect(image)
        cachedAutoGeneration = imageGeneration
        cachedAutoDetection = detection
        return detection
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

    /// Convert a SwiftUI `Color` to the engine's `RGB` (sRGB 8-bit).
    static func rgb(from color: Color) -> RGB {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return (
            UInt8((ns.redComponent * 255).rounded()),
            UInt8((ns.greenComponent * 255).rounded()),
            UInt8((ns.blueComponent * 255).rounded())
        )
    }

    func applyLogoPreset() {
        mode = .shapes
        autoColors = true
        autoColorMinFraction = 0.002
        simplicity = 0.10
        detail = 0.85
        straighten = 0.80
        smoothing = 0.35
        convert()
    }

    func loadLaunchArgumentIfPresent() {
        for arg in CommandLine.arguments.dropFirst()
        where FileManager.default.fileExists(atPath: arg) {
            load(path: arg)
            return
        }
    }
}
