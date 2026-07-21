import FekthorKit
import Foundation

// fekthor process <input> [--mode shapes] [--colors N] [--epsilon E]
//                         [--min-area A] [--out DIR]
// fekthor eval [--fixtures DIR] [--out DIR] [--json]

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data((msg + "\n").utf8))
    exit(1)
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
            + "  fekthor process <input> [--mode shapes|strokes|gradient] [--colors N] [--epsilon E] [--min-area A] [--out DIR]\n"
            + "  fekthor eval [--fixtures DIR] [--out DIR] [--json]")
}

// MARK: - process

func runProcess(_ args: [String]) {
    var args = args
    guard !args.isEmpty else { fail("missing <input>") }
    let input = args.removeFirst()

    var mode: Mode = .shapes
    var colors = 16
    var epsilon = 1.0
    var minArea = 6.0
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
        case "--out": i += 1; out = args[i]
        default: fail("unknown argument: \(args[i])")
        }
        i += 1
    }

    do {
        let img = try RasterImage.load(path: input)
        let result = try Fekthor.convert(
            img, mode: mode,
            options: Fekthor.Options(colors: colors, epsilon: epsilon, minArea: minArea))

        try FileManager.default.createDirectory(
            atPath: out, withIntermediateDirectories: true)
        try result.svg.write(toFile: out + "/vector.svg", atomically: true, encoding: .utf8)
        try result.rendered.savePNG(path: out + "/render.png")

        let q = result.quality
        let report: [String: Any] = [
            "input": input,
            "mode": mode.rawValue,
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
        ]
        let json = try JSONSerialization.data(
            withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: URL(fileURLWithPath: out + "/metrics.json"))

        let m = result.metrics
        print(
            String(
                format:
                    "mode=%@ fills=%d nodes=%d svg=%dKB | overall=%.3f fidelity=%.3f exact=%.2f%% psnr=%.2fdB",
                mode.rawValue, result.document.fillCount, result.document.nodeCount,
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
    let modes: [Mode] = [.shapes, .strokes, .gradient]

    // report.json rows exclude timestamps and timing so identical runs match byte
    // for byte (determinism gate). The printed table includes ms; JSON does not.
    var rows: [[String: Any]] = []

    print(
        String(
            format: "%-18@ %-9@ %8@ %9@ %11@ %6@ %6@ %6@",
            "fixture" as NSString, "mode" as NSString, "overall" as NSString,
            "fidelity" as NSString, "simplicity" as NSString, "nodes" as NSString,
            "paths" as NSString, "ms" as NSString))

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
                String(
                    format: "%-18@ %-9@ %8.3f %9.3f %11.3f %6d %6d %6d",
                    name as NSString, mode.rawValue as NSString, q.overall, q.fidelity,
                    q.simplicity, nodes, paths, ms))

            rows.append([
                "fixture": name,
                "mode": mode.rawValue,
                "overall": q.overall,
                "fidelity": q.fidelity,
                "simplicity": q.simplicity,
                "nodes": nodes,
                "paths": paths,
                "detail": q.detail,
            ])
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
