import Foundation

/// Auto mode resolves the source into one concrete faithful conversion mode.
///
/// Stage A is intentionally cheap and deterministic: all feature thresholds live
/// here so tuning is auditable against the fixture that motivated each gate.
public enum AutoMode {
    public struct Detection: Sendable {
        public var resolved: Mode
        public var confidence: Double
        public var features: [String: Double]
        public init(resolved: Mode, confidence: Double, features: [String: Double]) {
            self.resolved = resolved
            self.confidence = confidence
            self.features = features
        }
    }

    private struct Candidate {
        var mode: Mode
        var confidence: Double
    }

    // Stage-A thumbnail size: plan 06 fixture table requires the classifier to
    // run on the same 256px signal regardless of final working resolution.
    private static let thumbnailMaxDimension = 256
    // artist-lineart: greyscale ink stays below this channel-spread ceiling.
    private static let lineGreynessMax = 12.0
    // artist-lineart: anti-aliased black/white line art resolves to four grey buckets.
    private static let linePaletteMax = 4.5
    // artist-lineart: ink occupies less than a third of the page.
    private static let lineInkFractionMax = 0.35
    // artist-flat / thor-flat: flat artwork covers nearly all pixels with its palette.
    private static let flatCoverageMin = 0.90
    // artist-flat: crisp flat areas have little non-edge luminance drift.
    private static let flatGradientEnergyMax = 1.2
    // artist-3d / thor-3d: shaded sources keep measurable non-edge luminance drift.
    private static let gradientEnergyMin = 2.5
    // artist-3d / thor-3d: rendered artwork has many dominant colour bands.
    private static let gradientPaletteMin = 7.5
    // thor-flat: hard-edged flat artwork has denser edges than artist-3d at 256px.
    private static let flatEdgeDensityMin = 0.18
    // thor-flat: its antialiased borders lower palette coverage, but the hard-edge
    // density still distinguishes it from shaded artist-3d.
    private static let edgeFlatCoverageMin = 0.55
    // artist-flat: compact flat illustrations may quantize to six palette entries
    // and lower measured coverage after antialiasing, but remain low-palette sources.
    private static let lowPaletteFlatCoverageMin = 0.75
    // artist-flat: excludes artist-3d while keeping the flat illustration in Stage A.
    private static let flatPaletteMax = 6.5
    // artist-3d: shaded artwork may still have moderate flat coverage, so gradient
    // Stage A is limited to sources below this coverage unless edge-flat wins first.
    private static let gradientFlatCoverageMax = 0.75
    // thor-3d-flattened: AI-generated flat art measures low strict palette
    // coverage (soft texture/AA), but its interiors stay gentle and it produces
    // almost no quantization banding — genuinely shaded sources show both.
    private static let softFlatGradientEnergyMax = 5.0
    private static let softFlatBandinessMax = 0.015
    private static let softFlatCoverage24Min = 0.45
    // Plan 06 Stage-B boundary: Stage A is accepted only above this confidence.
    public static let trialConfidenceThreshold = 0.01

    public static func detect(_ img: RasterImage, options: Fekthor.Options = Fekthor.Options())
        -> Detection
    {
        let thumb = img.scaled(maxDimension: thumbnailMaxDimension)
        var features = computeFeatures(thumb)
        if let stageA = stageA(features) {
            features["stage"] = 1
            return Detection(
                resolved: stageA.mode, confidence: stageA.confidence, features: features)
        }
        let stageB = trialConversions(thumb, options: options)
        features["stage"] = 2
        for (mode, score) in stageB.scores {
            features["trial.\(mode.rawValue).overall"] = score
        }
        return Detection(resolved: stageB.mode, confidence: stageB.confidence, features: features)
    }

    static func computeFeatures(_ img: RasterImage) -> [String: Double] {
        let n = max(1, img.width * img.height)
        let palette = ColorQuantizer.quantizeAuto(img, maxColors: 12, minFraction: 0.01)
        let edge = sobel(img, threshold: 48)
        let dark = Foreground.dark(img, threshold: 128)

        var greynessSum = 0.0
        var flatCount = 0
        var flatCount24 = 0
        var gradientSum = 0.0
        var gradientSamples = 0
        for i in 0..<n {
            let o = i * 4
            let r = img.data[o], g = img.data[o + 1], b = img.data[o + 2]
            let mx = max(r, max(g, b))
            let mn = min(r, min(g, b))
            greynessSum += Double(Int(mx) - Int(mn))

            let p = palette.palette[palette.indices[i]]
            let dr = Int(r) - Int(p.r)
            let dg = Int(g) - Int(p.g)
            let db = Int(b) - Int(p.b)
            let d2 = dr * dr + dg * dg + db * db
            if d2 <= 10 * 10 { flatCount += 1 }
            if d2 <= 24 * 24 { flatCount24 += 1 }

            if !edge.map[i] {
                gradientSum += edge.gradient[i]
                gradientSamples += 1
            }
        }

        var features: [String: Double] = [:]
        features["greyness"] = greynessSum / Double(n)
        features["paletteCount"] = Double(palette.palette.count)
        features["flatCoverage"] = Double(flatCount) / Double(n)
        features["flatCoverage24"] = Double(flatCount24) / Double(n)
        features["bandiness"] = bandiness(
            indices: palette.indices, width: img.width, height: img.height)
        features["gradientEnergy"] =
            gradientSamples == 0 ? 0 : gradientSum / Double(gradientSamples)
        features["inkFraction"] = Double(dark.count) / Double(n)
        features["edgeDensity"] = Double(edge.count) / Double(n)
        return features
    }

    /// Fraction of significant quantized-region area made of thin stripes.
    /// Shaded (3D) sources quantize into elongated banding — high bandiness —
    /// while genuinely flat art quantizes into chunky regions. This is the
    /// direct signal for "would Shapes mode produce banding on this image".
    static func bandiness(indices: [Int], width w: Int, height h: Int) -> Double {
        let n = w * h
        guard n > 0 else { return 0 }
        var labels = [Int](repeating: -1, count: n)
        var stack = [Int]()
        var next = 0
        var significantArea = 0.0
        var bandedArea = 0.0
        for start in 0..<n where labels[start] == -1 {
            let color = indices[start]
            labels[start] = next
            stack.removeAll(keepingCapacity: true)
            stack.append(start)
            var area = 0
            var perimeter = 0
            while let i = stack.popLast() {
                area += 1
                let x = i % w, y = i / w
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
                    if nx < 0 || ny < 0 || nx >= w || ny >= h {
                        perimeter += 1
                        continue
                    }
                    let j = ny * w + nx
                    if indices[j] != color {
                        perimeter += 1
                    } else if labels[j] == -1 {
                        labels[j] = next
                        stack.append(j)
                    }
                }
            }
            next += 1
            // Ignore specks — bands worth worrying about are visible regions.
            guard area >= 30 else { continue }
            significantArea += Double(area)
            // Mean thickness of a long stripe ≈ 2·area / perimeter.
            let thickness = 2.0 * Double(area) / Double(max(1, perimeter))
            if thickness < 3.0 { bandedArea += Double(area) }
        }
        return significantArea == 0 ? 0 : bandedArea / significantArea
    }

    private static func stageA(_ f: [String: Double]) -> Candidate? {
        let greyness = f["greyness"] ?? .infinity
        let paletteCount = f["paletteCount"] ?? .infinity
        let flatCoverage = f["flatCoverage"] ?? 0
        let gradientEnergy = f["gradientEnergy"] ?? 0
        let inkFraction = f["inkFraction"] ?? 1
        let edgeDensity = f["edgeDensity"] ?? 0

        let lineMargins = [
            lineGreynessMax - greyness,
            linePaletteMax - paletteCount,
            lineInkFractionMax - inkFraction,
        ]
        if lineMargins.allSatisfy({ $0 > 0 }) {
            return Candidate(mode: .strokes, confidence: lineMargins.min() ?? 0)
        }

        let shapeMargins = [
            flatCoverage - flatCoverageMin,
            flatGradientEnergyMax - gradientEnergy,
        ]
        if shapeMargins.allSatisfy({ $0 > 0 }) {
            return Candidate(mode: .shapes, confidence: shapeMargins.min() ?? 0)
        }

        let edgeShapeMargins = [
            flatCoverage - edgeFlatCoverageMin,
            edgeDensity - flatEdgeDensityMin,
            lineInkFractionMax - inkFraction,
        ]
        if edgeShapeMargins.allSatisfy({ $0 > 0 }) {
            return Candidate(mode: .shapes, confidence: edgeShapeMargins.min() ?? 0)
        }

        let lowPaletteShapeMargins = [
            flatCoverage - lowPaletteFlatCoverageMin,
            flatPaletteMax - paletteCount,
            lineInkFractionMax - inkFraction,
        ]
        if lowPaletteShapeMargins.allSatisfy({ $0 > 0 }) {
            return Candidate(mode: .shapes, confidence: lowPaletteShapeMargins.min() ?? 0)
        }

        let flatCoverage24 = f["flatCoverage24"] ?? 0
        let bandiness = f["bandiness"] ?? 1
        // A carve-out of the gradient gate: only rich-palette sources that would
        // otherwise be claimed as gradient are rescued (low-palette flats are
        // handled by the earlier gates, ambiguous sources still reach Stage B).
        let softFlatMargins = [
            (softFlatGradientEnergyMax - gradientEnergy) / softFlatGradientEnergyMax,
            (softFlatBandinessMax - bandiness) / softFlatBandinessMax,
            flatCoverage24 - softFlatCoverage24Min,
            paletteCount - gradientPaletteMin,
        ]
        if softFlatMargins.allSatisfy({ $0 > 0 }) {
            return Candidate(mode: .shapes, confidence: softFlatMargins.min() ?? 0)
        }

        let gradientMargins = [
            gradientEnergy - gradientEnergyMin,
            paletteCount - gradientPaletteMin,
            gradientFlatCoverageMax - flatCoverage,
        ]
        if gradientMargins.allSatisfy({ $0 > 0 }) {
            return Candidate(mode: .gradient, confidence: gradientMargins.min() ?? 0)
        }
        return nil
    }

    private static func trialConversions(_ img: RasterImage, options: Fekthor.Options)
        -> (mode: Mode, confidence: Double, scores: [(Mode, Double)])
    {
        let modes: [Mode] = [.shapes, .strokes, .gradient]
        var scores: [(Mode, Double)] = []
        for mode in modes {
            guard let result = try? Fekthor.convertConcrete(img, mode: mode, options: options)
            else { continue }
            scores.append((mode, result.quality.overall))
        }
        scores.sort {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return modeRank($0.0) < modeRank($1.0)
        }
        guard let best = scores.first else {
            return (.shapes, 0, scores)
        }
        let second = scores.dropFirst().first?.1 ?? 0
        return (best.0, max(0, best.1 - second), scores)
    }

    private static func modeRank(_ mode: Mode) -> Int {
        switch mode {
        case .shapes: return 0
        case .strokes: return 1
        case .gradient: return 2
        case .auto: return 3
        }
    }

    private static func sobel(_ img: RasterImage, threshold: Double)
        -> (map: [Bool], gradient: [Double], count: Int)
    {
        let w = img.width
        let h = img.height
        let n = w * h
        var lum = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let o = i * 4
            lum[i] = Foreground.luminance(img.data[o], img.data[o + 1], img.data[o + 2])
        }
        var map = [Bool](repeating: false, count: n)
        var gradient = [Double](repeating: 0, count: n)
        var count = 0
        if w < 3 || h < 3 { return (map, gradient, count) }
        for y in 1..<(h - 1) {
            let r0 = (y - 1) * w
            let r1 = y * w
            let r2 = (y + 1) * w
            for x in 1..<(w - 1) {
                let tl = lum[r0 + x - 1], tc = lum[r0 + x], tr = lum[r0 + x + 1]
                let ml = lum[r1 + x - 1], mr = lum[r1 + x + 1]
                let bl = lum[r2 + x - 1], bc = lum[r2 + x], br = lum[r2 + x + 1]
                let gx = (tr + 2 * mr + br) - (tl + 2 * ml + bl)
                let gy = (bl + 2 * bc + br) - (tl + 2 * tc + tr)
                let g = (gx * gx + gy * gy).squareRoot()
                gradient[r1 + x] = g
                if g > threshold {
                    map[r1 + x] = true
                    count += 1
                }
            }
        }
        return (map, gradient, count)
    }
}
