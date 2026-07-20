import Foundation

/// A binary foreground mask (`true` = ink/foreground).
public struct Mask {
    public let width: Int
    public let height: Int
    public var fg: [Bool]

    @inline(__always)
    public func at(_ x: Int, _ y: Int) -> Bool {
        if x < 0 || y < 0 || x >= width || y >= height { return false }
        return fg[y * width + x]
    }

    public var count: Int { fg.lazy.filter { $0 }.count }
}

public enum Foreground {
    @inline(__always)
    static func luminance(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Double {
        0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)
    }

    /// Foreground = dark pixels (ink on light paper) below `threshold` luminance.
    public static func dark(_ img: RasterImage, threshold: UInt8) -> Mask {
        let n = img.width * img.height
        var fg = [Bool](repeating: false, count: n)
        for i in 0..<n {
            let o = i * 4
            let a = img.data[o + 3]
            fg[i] = a >= 128 && luminance(img.data[o], img.data[o + 1], img.data[o + 2]) < Double(threshold)
        }
        return Mask(width: img.width, height: img.height, fg: fg)
    }
}
