import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Straight-alpha RGBA8 image buffer, row-major, origin top-left.
public struct RasterImage: Sendable {
    public let width: Int
    public let height: Int
    /// `width * height * 4` bytes: R,G,B,A per pixel.
    public var data: [UInt8]

    public init(width: Int, height: Int, data: [UInt8]) {
        self.width = width
        self.height = height
        self.data = data
    }

    public enum ImageError: Error, CustomStringConvertible {
        case load(String)
        case save(String)
        public var description: String {
            switch self {
            case .load(let m): return "image load error: \(m)"
            case .save(let m): return "image save error: \(m)"
            }
        }
    }

    /// Load a raster image and normalise to RGBA8 in the sRGB space.
    public static func load(path: String) throws -> RasterImage {
        let url = URL(fileURLWithPath: path)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
            let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else {
            throw ImageError.load("cannot decode \(path)")
        }
        return try from(cgImage: cg)
    }

    /// Draw a CGImage into a known RGBA8 buffer (premultiplied last; opaque
    /// sources round-trip unchanged).
    public static func from(cgImage cg: CGImage) throws -> RasterImage {
        let width = cg.width
        let height = cg.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw ImageError.load("no sRGB colour space")
        }
        let bitmap = CGImageAlphaInfo.premultipliedLast.rawValue
        let ok = data.withUnsafeMutableBytes { buf -> Bool in
            guard
                let ctx = CGContext(
                    data: buf.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: space,
                    bitmapInfo: bitmap
                )
            else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        if !ok { throw ImageError.load("cannot create bitmap context") }
        return RasterImage(width: width, height: height, data: data)
    }

    @inline(__always)
    public func pixel(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        let i = (y * width + x) * 4
        return (data[i], data[i + 1], data[i + 2], data[i + 3])
    }

    /// Build a CGImage from the buffer (for Vision / display).
    public func cgImage() -> CGImage? {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmap = CGImageAlphaInfo.premultipliedLast.rawValue
        var d = data
        return d.withUnsafeMutableBytes { buf -> CGImage? in
            guard
                let ctx = CGContext(
                    data: buf.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: space, bitmapInfo: bitmap)
            else { return nil }
            return ctx.makeImage()
        }
    }

    public func savePNG(path: String) throws {
        guard let cg = cgImage() else { throw ImageError.save("no CGImage") }
        let url = URL(fileURLWithPath: path)
        guard
            let dest = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw ImageError.save("cannot create destination") }
        CGImageDestinationAddImage(dest, cg, nil)
        if !CGImageDestinationFinalize(dest) { throw ImageError.save("finalize failed") }
    }
}
