import CoreGraphics
import Foundation

/// RGBA8 pixels, origin top-left, y down. The internal coordinate system for everything in
/// PassportKit (see docs/ARCHITECTURE.md). Conversions happen only at the Vision and
/// Core Graphics boundaries.
public struct PixelImage: Sendable {
    public var width: Int
    public var height: Int
    /// Row-major RGBA, 4 bytes per pixel.
    public var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public init(width: Int, height: Int, fill: (r: UInt8, g: UInt8, b: UInt8)) {
        self.width = width
        self.height = height
        self.pixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            self.pixels[i] = fill.r
            self.pixels[i + 1] = fill.g
            self.pixels[i + 2] = fill.b
            self.pixels[i + 3] = 255
        }
    }

    public var size: CGSize { CGSize(width: width, height: height) }

    @inlinable
    public func offset(x: Int, y: Int) -> Int { (y * width + x) * 4 }

    public func clamped(x: Int, y: Int) -> (x: Int, y: Int) {
        (Swift.min(Swift.max(x, 0), width - 1), Swift.min(Swift.max(y, 0), height - 1))
    }
}

/// Single-channel float image, origin top-left. Used for luminance and for alpha mattes.
public struct GrayImage: Sendable {
    public var width: Int
    public var height: Int
    public var values: [Float]

    public init(width: Int, height: Int, values: [Float]) {
        self.width = width
        self.height = height
        self.values = values
    }

    public init(width: Int, height: Int, repeating value: Float = 0) {
        self.width = width
        self.height = height
        self.values = [Float](repeating: value, count: width * height)
    }

    @inlinable
    public subscript(x: Int, y: Int) -> Float {
        get { values[y * width + x] }
        set { values[y * width + x] = newValue }
    }

    public func at(x: Int, y: Int) -> Float {
        let cx = Swift.min(Swift.max(x, 0), width - 1)
        let cy = Swift.min(Swift.max(y, 0), height - 1)
        return values[cy * width + cx]
    }

    /// Bilinear sample in this image's pixel space.
    public func sample(x: Float, y: Float) -> Float {
        let x0 = Int(x.rounded(.down)), y0 = Int(y.rounded(.down))
        let fx = x - Float(x0), fy = y - Float(y0)
        let a = at(x: x0, y: y0), b = at(x: x0 + 1, y: y0)
        let c = at(x: x0, y: y0 + 1), d = at(x: x0 + 1, y: y0 + 1)
        return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy
    }

    /// Bilinear resize. Used to bring a Vision mask up to source resolution.
    public func resized(width newWidth: Int, height newHeight: Int) -> GrayImage {
        guard newWidth > 0, newHeight > 0 else { return GrayImage(width: 0, height: 0, values: []) }
        guard newWidth != width || newHeight != height else { return self }
        var out = GrayImage(width: newWidth, height: newHeight)
        let sx = Float(width) / Float(newWidth)
        let sy = Float(height) / Float(newHeight)
        for y in 0..<newHeight {
            let srcY = (Float(y) + 0.5) * sy - 0.5
            for x in 0..<newWidth {
                out[x, y] = sample(x: (Float(x) + 0.5) * sx - 0.5, y: srcY)
            }
        }
        return out
    }

    public func cropped(to rect: CGRect) -> GrayImage {
        let x0 = Int(rect.minX.rounded()), y0 = Int(rect.minY.rounded())
        let w = Int(rect.width.rounded()), h = Int(rect.height.rounded())
        var out = GrayImage(width: w, height: h)
        for y in 0..<h {
            for x in 0..<w {
                out[x, y] = at(x: x0 + x, y: y0 + y)
            }
        }
        return out
    }
}

/// A soft alpha matte for the subject: 1 inside, 0 in background.
public typealias AlphaMatte = GrayImage

public enum ImageConversion {
    /// Draws a CGImage into a known RGBA8 top-left buffer, so pixel access never depends on
    /// whatever colour space or layout the source happened to use.
    public static func pixelImage(from image: CGImage) -> PixelImage? {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = pixels.withUnsafeMutableBytes({ buffer -> CGContext? in
            CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: colorSpace, bitmapInfo: info
            )
        }) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return PixelImage(width: width, height: height, pixels: pixels)
    }

    public static func cgImage(from image: PixelImage) -> CGImage? {
        var pixels = image.pixels
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = pixels.withUnsafeMutableBytes({ buffer -> CGContext? in
            CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: colorSpace, bitmapInfo: info
            )
        }) else { return nil }
        return context.makeImage()
    }

    /// Rec. 709 luminance, 0-255.
    public static func luminance(of image: PixelImage) -> GrayImage {
        var out = GrayImage(width: image.width, height: image.height)
        for i in 0..<(image.width * image.height) {
            let r = Float(image.pixels[i * 4])
            let g = Float(image.pixels[i * 4 + 1])
            let b = Float(image.pixels[i * 4 + 2])
            out.values[i] = 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
        return out
    }

    /// Single-channel CGImage (a Vision mask) to a 0-1 matte.
    public static func matte(from image: CGImage) -> AlphaMatte? {
        guard let pixel = pixelImage(from: image) else { return nil }
        var out = GrayImage(width: pixel.width, height: pixel.height)
        for i in 0..<(pixel.width * pixel.height) {
            out.values[i] = Float(pixel.pixels[i * 4]) / 255
        }
        return out
    }
}
