import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Decodes a photo and bakes in its EXIF orientation, so every later stage works in one
/// coordinate system. iPhone HEIC always carries orientation (LESSONS 15).
public enum ImageLoader {

    public enum LoadError: Error, CustomStringConvertible {
        case unreadable(URL)
        case undecodable(URL)

        public var description: String {
            switch self {
            case let .unreadable(url): return "Could not open \(url.lastPathComponent)."
            case let .undecodable(url): return "Could not decode \(url.lastPathComponent) as an image."
            }
        }
    }

    public static func load(contentsOf url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw LoadError.unreadable(url)
        }
        return try load(source: source, label: url)
    }

    public static func load(data: Data, maxPixelSize: Int? = nil) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw LoadError.undecodable(URL(fileURLWithPath: "<data>"))
        }
        return try load(source: source, label: URL(fileURLWithPath: "<data>"), maxPixelSize: maxPixelSize)
    }

    /// Longest edge the pipeline will decode by default. A 24 MP photo already clears the required
    /// head pixels several times over, and decoding a 48 MP ProRAW at full size costs ~200 MB in
    /// pixel and luminance buffers alone. Downsampling on decode never drops below the head pixels
    /// the spec needs, so it does not count as upscaling (LESSONS 3).
    public static let defaultMaxPixelSize = 4500

    /// Scale factor that brings the longer edge down to `longestEdge`, never above 1.
    public static func workingScale(for image: CGImage, longestEdge: Int) -> Double {
        let longest = Double(max(image.width, image.height))
        guard longest > 0 else { return 1 }
        return min(1, Double(longestEdge) / longest)
    }

    /// Redraws at a fraction of the original size, for stages that do not need full resolution.
    public static func resized(_ image: CGImage, scale: Double) -> CGImage? {
        guard scale < 1 else { return image }
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// Decodes upright. ImageIO applies the EXIF transform itself with
    /// `kCGImageSourceCreateThumbnailWithTransform`, which avoids hand-rolled orientation
    /// matrices — those have to fight CGContext's bottom-left origin and got IMG_0012 upside
    /// down (Vision reported 178 deg of roll and a brow below the eyes).
    ///
    /// `maxPixelSize` caps the longer edge, which is also the downsample knob for very large
    /// inputs. Passing the true longer edge returns full resolution.
    private static func load(source: CGImageSource, label: URL, maxPixelSize: Int? = nil) throws -> CGImage {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let pixelWidth = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let pixelHeight = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let longestEdge = maxPixelSize ?? max(pixelWidth, pixelHeight, 1)

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longestEdge,
        ]
        if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return image
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw LoadError.undecodable(label)
        }
        return image
    }

    /// Loads with the longer edge capped, for memory control on 48 MP inputs.
    public static func load(contentsOf url: URL, maxPixelSize: Int) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw LoadError.unreadable(url)
        }
        return try load(source: source, label: url, maxPixelSize: maxPixelSize)
    }

    /// Redraws the image upright. Vision and every measurement afterwards then agree on axes.
    public static func applying(_ orientation: CGImagePropertyOrientation, to image: CGImage) -> CGImage? {
        guard orientation != .up else { return image }

        let w = CGFloat(image.width), h = CGFloat(image.height)
        let swapsAxes: Bool
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored: swapsAxes = true
        default: swapsAxes = false
        }
        let outWidth = Int(swapsAxes ? h : w)
        let outHeight = Int(swapsAxes ? w : h)

        var transform = CGAffineTransform.identity
        switch orientation {
        case .up: break
        case .upMirrored:
            transform = transform.translatedBy(x: w, y: 0).scaledBy(x: -1, y: 1)
        case .down:
            transform = transform.translatedBy(x: w, y: h).rotated(by: .pi)
        case .downMirrored:
            transform = transform.translatedBy(x: 0, y: h).scaledBy(x: 1, y: -1)
        case .left:
            transform = transform.translatedBy(x: 0, y: w).rotated(by: -.pi / 2)
        case .leftMirrored:
            transform = transform.rotated(by: -.pi / 2).scaledBy(x: -1, y: 1)
        case .right:
            transform = transform.translatedBy(x: h, y: 0).rotated(by: .pi / 2)
        case .rightMirrored:
            transform = transform.translatedBy(x: h, y: w).rotated(by: .pi / 2).scaledBy(x: -1, y: 1)
        @unknown default: break
        }

        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(
            data: nil, width: outWidth, height: outHeight,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace.model == .rgb ? colorSpace : CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: info
        ) else { return nil }

        context.concatenate(transform)
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return context.makeImage()
    }
}
