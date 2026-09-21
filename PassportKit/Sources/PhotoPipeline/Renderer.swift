import CoreGraphics
import Foundation
import PhotoAnalysis
import SpecKit

public struct RGB: Sendable, Equatable {
    public var r: Float, g: Float, b: Float

    public init(r: Float, g: Float, b: Float) {
        self.r = r; self.g = g; self.b = b
    }

    public static let white = RGB(r: 1, g: 1, b: 1)

    /// Parses `#RRGGBB` from a spec.
    public init?(hex: String) {
        var text = hex
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.r = Float((value >> 16) & 0xFF) / 255
        self.g = Float((value >> 8) & 0xFF) / 255
        self.b = Float(value & 0xFF) / 255
    }

    var bytes: (UInt8, UInt8, UInt8) {
        (UInt8((r * 255).rounded()), UInt8((g * 255).rounded()), UInt8((b * 255).rounded()))
    }
}

/// Cuts the subject out, drops it on the spec background and resamples once.
///
/// LESSONS 4: measure and composite at native resolution, then do exactly one area-averaging
/// downscale per output. LESSONS 10: sharpen only the subject, then revert the anti-aliased rim.
public enum Renderer {

    /// `matteScale` is source pixels to matte pixels. The matte is kept at the reduced working
    /// resolution it was refined at and sampled here, rather than being upscaled into another
    /// full-size buffer.
    public static func render(
        source: PixelImage, matte: AlphaMatte, matteScale: Double = 1, plan: CropPlan,
        background: RGB, sharpen: [SharpenPass], tuning: Tuning = .default
    ) -> PixelImage? {
        let outWidth = Int(plan.outputSize.width.rounded())
        let outHeight = Int(plan.outputSize.height.rounded())
        guard outWidth > 0, outHeight > 0 else { return nil }

        let x0 = Int(plan.rect.minX.rounded())
        let y0 = Int(plan.rect.minY.rounded())
        let cropWidth = Int(plan.rect.width.rounded())
        let cropHeight = Int(plan.rect.height.rounded())
        guard cropWidth > 0, cropHeight > 0 else { return nil }

        let wall = estimateBackgroundColour(
            source: source, matte: matte, matteScale: matteScale, rect: plan.rect
        )

        // Composite at source resolution, inside the crop only.
        var composite = [Float](repeating: 0, count: cropWidth * cropHeight * 3)
        var alpha = [Float](repeating: 0, count: cropWidth * cropHeight)

        for y in 0..<cropHeight {
            let sy = y0 + y
            for x in 0..<cropWidth {
                let sx = x0 + x
                let index = y * cropWidth + x
                // Outside the source the crop is pure background.
                guard sx >= 0, sx < source.width, sy >= 0, sy < source.height else {
                    composite[index * 3] = background.r
                    composite[index * 3 + 1] = background.g
                    composite[index * 3 + 2] = background.b
                    alpha[index] = 0
                    continue
                }
                let a = min(max(sampleMatte(matte, scale: matteScale, x: sx, y: sy), 0), 1)
                let p = source.offset(x: sx, y: sy)
                var colour = (
                    Float(source.pixels[p]) / 255,
                    Float(source.pixels[p + 1]) / 255,
                    Float(source.pixels[p + 2]) / 255
                )
                // Decontaminate: unmix the real wall out of partially transparent pixels, or
                // hair keeps a grey halo when it lands on white.
                if a > 0.02, a < 0.98 {
                    colour = (
                        unmix(colour.0, alpha: a, background: wall.r),
                        unmix(colour.1, alpha: a, background: wall.g),
                        unmix(colour.2, alpha: a, background: wall.b)
                    )
                }
                composite[index * 3] = colour.0 * a + background.r * (1 - a)
                composite[index * 3 + 1] = colour.1 * a + background.g * (1 - a)
                composite[index * 3 + 2] = colour.2 * a + background.b * (1 - a)
                alpha[index] = a
            }
        }

        // One area-averaging downscale (never two, LESSONS 4).
        let downscaled = areaAverage(
            composite, width: cropWidth, height: cropHeight, channels: 3,
            newWidth: outWidth, newHeight: outHeight
        )
        let downscaledAlpha = areaAverage(
            alpha, width: cropWidth, height: cropHeight, channels: 1,
            newWidth: outWidth, newHeight: outHeight
        )

        var out = PixelImage(width: outWidth, height: outHeight, fill: background.bytes)
        for i in 0..<(outWidth * outHeight) {
            out.pixels[i * 4] = byte(downscaled[i * 3])
            out.pixels[i * 4 + 1] = byte(downscaled[i * 3 + 1])
            out.pixels[i * 4 + 2] = byte(downscaled[i * 3 + 2])
            out.pixels[i * 4 + 3] = 255
        }

        let unsharpened = out
        for pass in sharpen {
            out = unsharpMask(out, radius: pass.radius, amount: pass.amount)
        }

        // Background is the spec colour exactly; the soft rim keeps its unsharpened value so
        // sharpening cannot draw a dark halo along the silhouette.
        let (br, bg, bb) = background.bytes
        for i in 0..<(outWidth * outHeight) {
            let a = downscaledAlpha[i]
            if a <= tuning.sharpenAlphaFloor {
                out.pixels[i * 4] = br
                out.pixels[i * 4 + 1] = bg
                out.pixels[i * 4 + 2] = bb
            } else if a < 0.98 {
                out.pixels[i * 4] = unsharpened.pixels[i * 4]
                out.pixels[i * 4 + 1] = unsharpened.pixels[i * 4 + 1]
                out.pixels[i * 4 + 2] = unsharpened.pixels[i * 4 + 2]
            }
        }
        return out
    }

    static func sampleMatte(_ matte: AlphaMatte, scale: Double, x: Int, y: Int) -> Float {
        guard scale < 1 else { return matte.at(x: x, y: y) }
        return matte.sample(x: Float(Double(x) * scale), y: Float(Double(y) * scale))
    }

    static func unmix(_ observed: Float, alpha: Float, background: Float) -> Float {
        guard alpha > 0.02 else { return observed }
        return min(max((observed - (1 - alpha) * background) / alpha, 0), 1)
    }

    /// Mean colour of pixels the matte calls background, inside the crop. That is the real wall,
    /// which is what has to be unmixed out of the edges.
    static func estimateBackgroundColour(
        source: PixelImage, matte: AlphaMatte, matteScale: Double, rect: CGRect
    ) -> RGB {
        var r: Double = 0, g: Double = 0, b: Double = 0, count: Double = 0
        let x0 = max(0, Int(rect.minX)), x1 = min(source.width - 1, Int(rect.maxX))
        let y0 = max(0, Int(rect.minY)), y1 = min(source.height - 1, Int(rect.maxY))
        guard x1 > x0, y1 > y0 else { return .white }

        let step = max(1, (x1 - x0) / 200)
        for y in stride(from: y0, through: y1, by: step) {
            for x in stride(from: x0, through: x1, by: step)
            where sampleMatte(matte, scale: matteScale, x: x, y: y) < 0.05 {
                let p = source.offset(x: x, y: y)
                r += Double(source.pixels[p])
                g += Double(source.pixels[p + 1])
                b += Double(source.pixels[p + 2])
                count += 1
            }
        }
        guard count > 0 else { return .white }
        return RGB(
            r: Float(r / count / 255), g: Float(g / count / 255), b: Float(b / count / 255)
        )
    }

    static func areaAverage(
        _ values: [Float], width: Int, height: Int, channels: Int,
        newWidth: Int, newHeight: Int
    ) -> [Float] {
        var out = [Float](repeating: 0, count: newWidth * newHeight * channels)
        let sx = Double(width) / Double(newWidth)
        let sy = Double(height) / Double(newHeight)

        for y in 0..<newHeight {
            let srcY0 = Int(Double(y) * sy)
            let srcY1 = max(srcY0 + 1, min(height, Int((Double(y) + 1) * sy)))
            for x in 0..<newWidth {
                let srcX0 = Int(Double(x) * sx)
                let srcX1 = max(srcX0 + 1, min(width, Int((Double(x) + 1) * sx)))
                var sums = [Float](repeating: 0, count: channels)
                var count: Float = 0
                for yy in srcY0..<srcY1 {
                    for xx in srcX0..<srcX1 {
                        let index = (yy * width + xx) * channels
                        for c in 0..<channels { sums[c] += values[index + c] }
                        count += 1
                    }
                }
                let outIndex = (y * newWidth + x) * channels
                for c in 0..<channels { out[outIndex + c] = count > 0 ? sums[c] / count : 0 }
            }
        }
        return out
    }

    static func unsharpMask(_ image: PixelImage, radius: Double, amount: Double) -> PixelImage {
        let blurred = gaussianBlur(image, radius: radius)
        var out = image
        for i in 0..<(image.width * image.height) {
            for c in 0..<3 {
                let base = Float(image.pixels[i * 4 + c])
                var high = base - Float(blurred.pixels[i * 4 + c])
                // Ignore differences small enough to be noise (the Python does the same).
                if abs(high) < 2 { high = 0 }
                out.pixels[i * 4 + c] = byte((base + Float(amount) * high) / 255)
            }
        }
        return out
    }

    static func gaussianBlur(_ image: PixelImage, radius: Double) -> PixelImage {
        let sigma = max(radius, 0.1)
        let kernelRadius = max(1, Int((sigma * 3).rounded()))
        var kernel = [Float](repeating: 0, count: kernelRadius * 2 + 1)
        var total: Float = 0
        for i in 0...(kernelRadius * 2) {
            let d = Float(i - kernelRadius)
            let v = expf(-(d * d) / Float(2 * sigma * sigma))
            kernel[i] = v
            total += v
        }
        for i in kernel.indices { kernel[i] /= total }

        var horizontal = image
        for y in 0..<image.height {
            for x in 0..<image.width {
                var sums = [Float](repeating: 0, count: 3)
                for k in -kernelRadius...kernelRadius {
                    let (cx, _) = image.clamped(x: x + k, y: y)
                    let p = image.offset(x: cx, y: y)
                    let weight = kernel[k + kernelRadius]
                    for c in 0..<3 { sums[c] += Float(image.pixels[p + c]) * weight }
                }
                let p = image.offset(x: x, y: y)
                for c in 0..<3 { horizontal.pixels[p + c] = byte(sums[c] / 255) }
            }
        }

        var out = horizontal
        for y in 0..<image.height {
            for x in 0..<image.width {
                var sums = [Float](repeating: 0, count: 3)
                for k in -kernelRadius...kernelRadius {
                    let (_, cy) = image.clamped(x: x, y: y + k)
                    let p = horizontal.offset(x: x, y: cy)
                    let weight = kernel[k + kernelRadius]
                    for c in 0..<3 { sums[c] += Float(horizontal.pixels[p + c]) * weight }
                }
                let p = image.offset(x: x, y: y)
                for c in 0..<3 { out.pixels[p + c] = byte(sums[c] / 255) }
            }
        }
        return out
    }

    static func byte(_ value: Float) -> UInt8 {
        UInt8(min(max(value * 255, 0), 255).rounded())
    }
}
