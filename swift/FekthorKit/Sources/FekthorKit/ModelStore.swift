import CoreML
import Foundation

/// Optional on-device model management (docs/AI.md, docs/PRIVACY-SECURITY.md):
/// models are never bundled or required — they download on an explicit user
/// action from the owner's R2 bucket (same source ImageKid uses), are compiled
/// once, and cached in Application Support. Every feature degrades cleanly
/// when its model is absent.
public enum ModelStore {
    public enum Model: String, CaseIterable, Sendable {
        case realESRGAN = "RealESRGAN"

        public var approxSize: String {
            switch self {
            case .realESRGAN: return "33 MB"
            }
        }
    }

    /// Public R2 custom domain; models live under `v1/<Name>/…` as the three
    /// files of a single-model `.mlpackage`.
    static let baseURL = URL(string: "https://models-data.hakobs.com/v1")!
    static let packageFiles: [(remote: String, local: String)] = [
        ("Manifest.json", "Manifest.json"),
        ("model.mlmodel", "Data/com.apple.CoreML/model.mlmodel"),
        ("weight.bin", "Data/com.apple.CoreML/weights/weight.bin"),
    ]

    public static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fekthor/Models", isDirectory: true)
    }

    public static func compiledURL(_ model: Model) -> URL {
        directory.appendingPathComponent("\(model.rawValue).mlmodelc", isDirectory: true)
    }

    public static func isInstalled(_ model: Model) -> Bool {
        FileManager.default.fileExists(atPath: compiledURL(model).path)
    }

    /// Download the package files, reassemble, compile, and cache. Throws on
    /// any failure; partial downloads are cleaned up.
    public static func download(_ model: Model) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let staging = directory.appendingPathComponent(
            "\(model.rawValue).mlpackage", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        try? fm.removeItem(at: staging)
        for (remote, local) in packageFiles {
            let src = baseURL.appendingPathComponent("\(model.rawValue)/\(remote)")
            let dst = staging.appendingPathComponent(local)
            try fm.createDirectory(
                at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            let (tmp, response) = try await URLSession.shared.download(from: src)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            try? fm.removeItem(at: dst)
            try fm.moveItem(at: tmp, to: dst)
        }
        let compiled = try await MLModel.compileModel(at: staging)
        let dest = compiledURL(model)
        try? fm.removeItem(at: dest)
        try fm.moveItem(at: compiled, to: dest)
    }

    public static func remove(_ model: Model) {
        try? FileManager.default.removeItem(at: compiledURL(model))
    }
}
