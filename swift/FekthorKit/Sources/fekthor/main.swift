import FekthorKit
import Foundation

// fekthor process <input> [--mode shapes] [--colors N] [--epsilon E]
//                         [--min-area A] [--out DIR]

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data((msg + "\n").utf8))
    exit(1)
}

var args = Array(CommandLine.arguments.dropFirst())
guard args.first == "process" else {
    fail(
        "usage: fekthor process <input> [--mode shapes] [--colors N] [--epsilon E] [--min-area A] [--out DIR]"
    )
}
args.removeFirst()
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
    ]
    let json = try JSONSerialization.data(
        withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    try json.write(to: URL(fileURLWithPath: out + "/metrics.json"))

    let m = result.metrics
    print(
        String(
            format:
                "mode=%@ fills=%d nodes=%d svg=%dKB | exact=%.2f%% mean_abs=%.2f psnr=%.2fdB",
            mode.rawValue, result.document.fillCount, result.document.nodeCount,
            result.svg.utf8.count / 1024, m.exactPct, m.meanAbs, m.psnr))
} catch {
    fail("error: \(error)")
}
