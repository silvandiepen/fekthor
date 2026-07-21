// swift-tools-version: 5.9
import PackageDescription

// FekthorKit — the shared Swift engine for Fekthor's native apps.
//
// Deterministic raster-to-vector pipeline: image analysis, colour quantization,
// contour tracing, centreline strokes, gradients, document model, SVG export and
// render-back comparison. UI-free and testable without the app.
let package = Package(
    name: "FekthorKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "FekthorKit", targets: ["FekthorKit"]),
        .executable(name: "fekthor", targets: ["fekthor"]),
    ],
    targets: [
        // Optimise the engine even in Debug builds — the per-pixel loops are far
        // too slow at -Onone, and the app is normally built in Debug.
        .target(
            name: "FekthorKit",
            swiftSettings: [.unsafeFlags(["-O"], .when(configuration: .debug))]),
        .executableTarget(name: "fekthor", dependencies: ["FekthorKit"]),
        .testTarget(name: "FekthorKitTests", dependencies: ["FekthorKit"]),
    ]
)
