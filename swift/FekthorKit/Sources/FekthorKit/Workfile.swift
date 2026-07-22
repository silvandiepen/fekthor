import Foundation

/// The `.fekthor` workfile, v1 (plan 08, step 8; decision D-022).
///
/// A Codable-JSON workspace configuration: a folder reference (icon
/// workspaces are folders of plain SVGs owned by other tools too), optional
/// embedded artboards — geometry embedded **as SVG text**, so there is exactly
/// one geometry serialisation path (`SVGReader`/`SVGWriter`) — and
/// forward-compatible stubs for the P2/P3 features (categories, export
/// profiles, style tokens, container slots).
///
/// Contracts:
/// - Deterministic encoding (`.sortedKeys`, pretty-printed, slashes
///   unescaped) so a workfile diff is reviewable.
/// - Tolerant decoding: unknown keys are ignored, every section is optional,
///   and `version` gates future migrations.
public struct Workfile: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var folder: FolderReference?
    public var artboards: [Artboard]?
    public var categories: [String]?
    public var exportProfiles: [ExportProfile]?
    public var styleTokens: [StyleToken]?
    public var containers: [ContainerSlot]?

    public init(
        version: Int = Workfile.currentVersion,
        folder: FolderReference? = nil,
        artboards: [Artboard]? = nil,
        categories: [String]? = nil,
        exportProfiles: [ExportProfile]? = nil,
        styleTokens: [StyleToken]? = nil,
        containers: [ContainerSlot]? = nil
    ) {
        self.version = version
        self.folder = folder
        self.artboards = artboards
        self.categories = categories
        self.exportProfiles = exportProfiles
        self.styleTokens = styleTokens
        self.containers = containers
    }

    /// A workspace folder: the display path plus a security-scoped bookmark
    /// (created app-side; the sandbox needs it to reopen the folder later).
    public struct FolderReference: Codable, Equatable, Sendable {
        public var path: String
        public var bookmark: Data?
        public init(path: String, bookmark: Data? = nil) {
            self.path = path
            self.bookmark = bookmark
        }
    }

    /// An embedded artboard: name + geometry as SVG text.
    public struct Artboard: Codable, Equatable, Sendable {
        public var name: String
        public var svg: String
        public init(name: String, svg: String) {
            self.name = name
            self.svg = svg
        }
    }

    /// P2 stub: a named export pipeline (actions land with plan 08 P2).
    public struct ExportProfile: Codable, Equatable, Sendable {
        public var name: String
        public init(name: String) {
            self.name = name
        }
    }

    /// P3 stub: a colour-slot style token (D-023) — slot name + canonical
    /// colour string it matches (e.g. outline = "#010101").
    public struct StyleToken: Codable, Equatable, Sendable {
        public var name: String
        public var color: String
        public init(name: String, color: String) {
            self.name = name
            self.color = color
        }
    }

    /// P2 stub: a container slot (D-023) — the container icon's workspace
    /// name plus the slot rect content icons are fitted into.
    public struct ContainerSlot: Codable, Equatable, Sendable {
        public var icon: String
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double
        public var fit: String?
        public init(icon: String, x: Double, y: Double, width: Double, height: Double, fit: String? = nil) {
            self.icon = icon
            self.x = x
            self.y = y
            self.width = width
            self.height = height
            self.fit = fit
        }
    }

    // MARK: - Serialisation

    public func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> Workfile {
        try JSONDecoder().decode(Workfile.self, from: data)
    }
}
