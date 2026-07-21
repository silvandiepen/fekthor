import FekthorKit
import Foundation

// fekthor process <input> [--mode auto] [--colors N] [--epsilon E]
//                         [--min-area A] [--out DIR]
// fekthor eval [--fixtures DIR] [--out DIR] [--json]

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data((msg + "\n").utf8))
    exit(1)
}

func modeLabel(requested: Mode, resolved: Mode) -> String {
    requested == .auto ? "auto→\(resolved.rawValue)" : requested.rawValue
}

func canonicalMode(for fixture: String) -> Mode? {
    switch fixture {
    case "artist-lineart": return .strokes
    case "artist-flat", "thor-flat": return .shapes
    case "artist-3d", "thor-3d": return .gradient
    default: return nil
    }
}

var args = Array(CommandLine.arguments.dropFirst())
let sub = args.first
switch sub {
case "process":
    args.removeFirst()
    runProcess(args)
case "eval":
    args.removeFirst()
    runEval(args)
default:
    fail(
        "usage:\n"
            + "  fekthor process <input> [--mode auto|shapes|strokes|gradient] [--preset logo] [--colors N] [--epsilon E] [--flatten 0..1] [--min-area A] [--out DIR]\n"
            + "  fekthor eval [--fixtures DIR] [--out DIR] [--json]")
}

// MARK: - process

func runProcess(_ args: [String]) {
    var args = args
    guard !args.isEmpty else { fail("missing <input>") }
    let input = args.removeFirst()

    var mode: Mode = .auto
    var colors = 16
    var epsilon = 1.0
    var minArea = 6.0
    var simplicity = 0.3
    var smoothing = 1.0
    var straighten = 0.5
    var autoColors = true
    var autoColorMinFraction = 0.004
    var flatten = 0.0
    var out = "out"

    var i = 0
    while i < args.count {
        switch args[i] {
        case "--mode":
            i += 1
            guard i < args.count, let m = Mode(rawValue: args[i]) else { fail("bad --mode") }
            mode = m
        case "--colors": i += 1; colors = Int(args[i]) ?? colors
        case "--epsilon": i += 1; epsilon = Double(args[i]) ?? epsilon
        case "--min-area": i += 1; minArea = Double(args[i]) ?? minArea
        case "--simplicity": i += 1; simplicity = Double(args[i]) ?? simplicity
        case "--smoothing": i += 1; smoothing = Double(args[i]) ?? smoothing
        case "--straighten": i += 1; straighten = Double(args[i]) ?? straighten
        case "--flatten":
            i += 1
            flatten = min(1.0, max(0.0, Double(args[i]) ?? flatten))
        case "--auto-colors": autoColors = true
        case "--fixed-colors": autoColors = false
        case "--preset":
            i += 1
            guard i < args.count else { fail("missing --preset value") }
            switch args[i] {
            case "logo":
                autoColors = true
                autoColorMinFraction = 0.002
                simplicity = 0.10
                // CLI epsilon is the direct engine tolerance; this matches the
                // app's Detail 85% mapping (4.2 - 3.9 * 0.85).
                epsilon = 0.885
                straighten = 0.80
                smoothing = 0.35
            default:
                fail("bad --preset")
            }
        case "--out": i += 1; out = args[i]
        default: fail("unknown argument: \(args[i])")
        }
        i += 1
    }

    do {
        let img = try RasterImage.load(path: input)
        let result = try Fekthor.convert(
            img, mode: mode,
            options: Fekthor.Options(
                colors: colors, epsilon: epsilon, minArea: minArea,
                simplicity: simplicity, smoothing: smoothing, straighten: straighten,
                autoColors: autoColors, autoColorMinFraction: autoColorMinFraction,
                flatten: flatten))

        try FileManager.default.createDirectory(
            atPath: out, withIntermediateDirectories: true)
        try result.svg.write(toFile: out + "/vector.svg", atomically: true, encoding: .utf8)
        try result.rendered.savePNG(path: out + "/render.png")

        let q = result.quality
        let report: [String: Any] = [
            "input": input,
            "mode": mode.rawValue,
            "resolvedMode": result.resolvedMode.rawValue,
            "width": img.width, "height": img.height,
            "fills": result.document.fillCount,
            "strokes": result.document.strokeCount,
            "nodes": result.document.nodeCount,
            "svgBytes": result.svg.utf8.count,
            "metrics": [
                "meanAbs": result.metrics.meanAbs,
                "exactPct": result.metrics.exactPct,
                "psnr": result.metrics.psnr,
                "tolerance": result.metrics.tolerance,
            ],
            "quality": [
                "overall": q.overall,
                "fidelity": q.fidelity,
                "simplicity": q.simplicity,
                "detail": q.detail,
            ],
            "detail": result.detail,
            "background": result.detail["backgroundTransparent"] == 1 ? "transparent" : "solid",
        ]
        let json = try JSONSerialization.data(
            withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: URL(fileURLWithPath: out + "/metrics.json"))

        let m = result.metrics
        print(
            String(
                format:
                    "mode=%@ fills=%d nodes=%d svg=%dKB | overall=%.3f fidelity=%.3f exact=%.2f%% psnr=%.2fdB",
                modeLabel(requested: mode, resolved: result.resolvedMode),
                result.document.fillCount, result.document.nodeCount,
                result.svg.utf8.count / 1024, q.overall, q.fidelity, m.exactPct, m.psnr))
    } catch {
        fail("error: \(error)")
    }
}

// MARK: - eval

func runEval(_ args: [String]) {
    // Working resolution — matches the app default (`RasterImage.scaled(1024)`).
    // A local (not a file-scope global): top-level `main.swift` runs in order, so a
    // global declared below the dispatch would still be 0 when `runEval` executes.
    let evalWorkingSize = 1024
    var fixturesDir = "fixtures/inputs"
    var out = "out/eval"
    var writeJSON = false

    var i = 0
    while i < args.count {
        switch args[i] {
        case "--fixtures": i += 1; fixturesDir = i < args.count ? args[i] : fixturesDir
        case "--out": i += 1; out = i < args.count ? args[i] : out
        case "--json": writeJSON = true
        default: fail("unknown argument: \(args[i])")
        }
        i += 1
    }

    let fm = FileManager.default
    guard let entries = try? fm.contentsOfDirectory(atPath: fixturesDir) else {
        fail("cannot read fixtures dir: \(fixturesDir)")
    }
    // Deterministic ordering: fixtures sorted by name, modes in a fixed order.
    let fixtures = entries.filter { $0.lowercased().hasSuffix(".png") }.sorted()
    let modes: [Mode] = [.auto, .shapes, .strokes, .gradient]

    // report.json rows exclude timestamps and timing so identical runs match byte
    // for byte (determinism gate). The printed table includes ms; JSON does not.
    var rows: [[String: Any]] = []

    // `String(format:)` ignores field widths on `%@`, so pad columns by hand.
    func padR(_ s: String, _ n: Int) -> String {
        s.count >= n ? s : s + String(repeating: " ", count: n - s.count)
    }
    func padL(_ s: String, _ n: Int) -> String {
        s.count >= n ? s : String(repeating: " ", count: n - s.count) + s
    }
    print(
        padR("fixture", 18) + " " + padR("mode", 14) + " " + padL("overall", 8) + " "
            + padL("fidelity", 9) + " " + padL("simplicity", 11) + " " + padL("nodes", 6) + " "
            + padL("paths", 6) + " " + padL("ms", 6))

    for fixture in fixtures {
        let name = (fixture as NSString).deletingPathExtension
        let path = fixturesDir + "/" + fixture
        guard let full = try? RasterImage.load(path: path) else {
            FileHandle.standardError.write(Data(("skip (load failed): \(path)\n").utf8))
            continue
        }
        let working = full.scaled(maxDimension: evalWorkingSize)
        for mode in modes {
            let start = Date()
            guard let result = try? Fekthor.convert(working, mode: mode) else {
                FileHandle.standardError.write(Data(("skip (convert failed): \(path) \(mode.rawValue)\n").utf8))
                continue
            }
            let ms = Int((Date().timeIntervalSince(start) * 1000).rounded())
            let q = result.quality
            let nodes = result.document.nodeCount
            let paths = result.document.elements.count

            // Persist per-run artefacts for visual review.
            let runDir = "\(out)/\(name)/\(mode.rawValue)"
            try? fm.createDirectory(atPath: runDir, withIntermediateDirectories: true)
            try? result.svg.write(toFile: runDir + "/vector.svg", atomically: true, encoding: .utf8)
            try? result.rendered.savePNG(path: runDir + "/render.png")

            print(
                padR(name, 18) + " " + padR(modeLabel(requested: mode, resolved: result.resolvedMode), 14) + " "
                    + padL(String(format: "%.3f", q.overall), 8) + " "
                    + padL(String(format: "%.3f", q.fidelity), 9) + " "
                    + padL(String(format: "%.3f", q.simplicity), 11) + " "
                    + padL("\(nodes)", 6) + " " + padL("\(paths)", 6) + " " + padL("\(ms)", 6))

            var row: [String: Any] = [
                "fixture": name,
                "mode": mode.rawValue,
                "resolvedMode": result.resolvedMode.rawValue,
                "overall": q.overall,
                "fidelity": q.fidelity,
                "simplicity": q.simplicity,
                "nodes": nodes,
                "paths": paths,
                "detail": q.detail.merging(result.detail) { current, _ in current },
                "background": result.detail["backgroundTransparent"] == 1 ? "transparent" : "solid",
            ]
            if mode == .auto, let expected = canonicalMode(for: name) {
                row["expectedResolvedMode"] = expected.rawValue
                row["resolvedModeOK"] = result.resolvedMode == expected
            }
            rows.append(row)
        }
    }

    if writeJSON {
        do {
            try fm.createDirectory(atPath: out, withIntermediateDirectories: true)
            let report: [String: Any] = ["runs": rows]
            let json = try JSONSerialization.data(
                withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try json.write(to: URL(fileURLWithPath: out + "/report.json"))
        } catch {
            fail("error writing report.json: \(error)")
        }
    }
}
