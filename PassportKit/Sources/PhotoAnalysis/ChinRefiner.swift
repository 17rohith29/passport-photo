import CoreGraphics
import Foundation

/// Finds the true bottom of the chin, which on a bearded face sits below the landmark chin.
///
/// LESSONS 1: dlib's chin landed 3.7-5% of head height high on the owner's beard. Vision's
/// landmark chin is measured at +2.3% on IMG_0012 (see docs/PROGRESS.md), same direction.
/// Ported from `reference/python/chin.py`: walk down a centre strip until beard texture falls
/// to the smooth-neck level, with a light-to-dark edge fallback for clean-shaven faces.
public enum ChinRefiner {

    public struct Debug: Sendable {
        public var landmarkChinY: CGFloat
        public var textureChinY: CGFloat
        public var edgeChinY: CGFloat
        public var bearded: Bool
        public var chinTexture: Float
        public var neckTexture: Float
    }

    public static func refine(
        luminance: GrayImage, face: FaceMeasurements, tuning: Tuning = .default
    ) -> CGFloat {
        refineWithDebug(luminance: luminance, face: face, tuning: tuning).0
    }

    public static func refineWithDebug(
        luminance: GrayImage, face: FaceMeasurements, tuning: Tuning = .default
    ) -> (CGFloat, Debug?) {
        let faceWidth = Double(face.faceWidth)
        let chinY = Double(face.rawChin.y)
        let faceHeight = chinY - Double(face.browY)
        guard faceWidth > 0, faceHeight > 0 else { return (face.rawChin.y, nil) }

        let halfWidth = max(2, Int((tuning.chinStripHalfWidth * faceWidth).rounded()))
        let centreX = Int(face.rawChin.x.rounded())
        let y0 = Int((chinY - tuning.chinSearchAbove * faceHeight).rounded())
        let y1 = Int((chinY + tuning.chinSearchBelow * faceHeight).rounded())
        guard y1 > y0 + 4 else { return (face.rawChin.y, nil) }

        // Row profiles down the strip: texture energy (beard hair is high frequency) and luminance.
        var texture = [Float](repeating: 0, count: y1 - y0)
        var luma = [Float](repeating: 0, count: y1 - y0)
        for (index, y) in (y0..<y1).enumerated() {
            var textureSum: Float = 0
            var lumaSum: Float = 0
            var count: Float = 0
            for x in (centreX - halfWidth)...(centreX + halfWidth) {
                let laplacian = -4 * luminance.at(x: x, y: y)
                    + luminance.at(x: x - 1, y: y) + luminance.at(x: x + 1, y: y)
                    + luminance.at(x: x, y: y - 1) + luminance.at(x: x, y: y + 1)
                textureSum += abs(laplacian)
                lumaSum += luminance.at(x: x, y: y)
                count += 1
            }
            texture[index] = textureSum / max(count, 1)
            luma[index] = lumaSum / max(count, 1)
        }

        let smoothing = max(1, Int((0.012 * faceHeight).rounded()))
        texture = smooth(texture, radius: smoothing)
        luma = smooth(luma, radius: max(1, Int((0.008 * faceHeight).rounded())))

        let headWindow = max(1, Int((0.10 * faceHeight).rounded()))
        let neckWindow = max(1, Int((0.06 * faceHeight).rounded()))
        let chinTexture = median(Array(texture.prefix(min(headWindow, texture.count))))
        let neckTexture = median(Array(texture.suffix(min(neckWindow, texture.count))))

        let start = min(max(1, Int((tuning.chinSearchAbove * faceHeight).rounded())), texture.count - 1)
        let threshold = neckTexture + tuning.chinTextureThreshold * (chinTexture - neckTexture)

        var textureChin = texture.count - 1
        for index in start..<texture.count where texture[index] < threshold {
            textureChin = index
            break
        }

        // Clean-shaven fallback: the strongest light-to-dark step is the chin edge.
        var edgeChin = start
        var steepest = Float.greatestFiniteMagnitude
        for index in start..<(luma.count - 1) {
            let delta = luma[index + 1] - luma[index]
            if delta < steepest {
                steepest = delta
                edgeChin = index
            }
        }

        let bearded = chinTexture > tuning.beardedTextureRatio * neckTexture
        let chosen = bearded ? textureChin : edgeChin
        let debug = Debug(
            landmarkChinY: face.rawChin.y,
            textureChinY: CGFloat(y0 + textureChin),
            edgeChinY: CGFloat(y0 + edgeChin),
            bearded: bearded,
            chinTexture: chinTexture,
            neckTexture: neckTexture
        )
        return (CGFloat(y0 + chosen), debug)
    }

    static func smooth(_ values: [Float], radius: Int) -> [Float] {
        guard radius > 0, values.count > 2 * radius else { return values }
        var out = values
        for i in values.indices {
            let lower = max(0, i - radius), upper = min(values.count - 1, i + radius)
            var sum: Float = 0
            for j in lower...upper { sum += values[j] }
            out[i] = sum / Float(upper - lower + 1)
        }
        return out
    }

    static func median(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
