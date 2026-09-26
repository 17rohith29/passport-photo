import CoreGraphics
import Foundation
import PhotoAnalysis

/// Background and lighting, measured on a live camera frame.
///
/// The point is to say "that wall won't work" while the person can still move, rather than after
/// they have taken the photo. These are deliberately cheap: they run on a downscaled frame a few
/// times a second, and they sample the wall beside the head instead of segmenting anything.
///
/// They are hints, not compliance checks. The pipeline replaces the background, so a busy wall is
/// not a rejection — but it makes the cut-out worse, which is what produces the mangled edges
/// LESSONS 20 is about. Lighting is different: an unevenly lit face is a real check that will
/// fail later and cannot be fixed afterwards.
public enum FrameQuality {

    public struct Reading: Sendable, Equatable {
        /// Mean brightness of the wall beside the head, 0 (black) to 1 (white).
        public var backgroundBrightness: Double
        /// How much the wall varies: 0 is perfectly plain, higher means patterned, a doorway, a
        /// picture frame, or a second room visible behind the person.
        public var backgroundVariation: Double
        /// Left/right facial brightness difference, the same metric the import path checks.
        public var cheekImbalance: Double
        /// False when the frame gave us nothing to measure, so callers can stay silent.
        public var isUsable: Bool

        public static let unusable = Reading(
            backgroundBrightness: 0, backgroundVariation: 0, cheekImbalance: 0, isUsable: false
        )
    }

    /// Below this the wall is too dark for a clean cut-out.
    ///
    /// Calibrated, not invented: on 14 real attempts at a passport photo this metric reads
    /// 0.48-0.79, while the 192 measurable calibration portraits sit at p25 = 0.18. 0.40 leaves
    /// margin under the worst genuine attempt, so someone actually trying is never nagged.
    public static let darkBackgroundBelow = 0.40

    /// Deliberately NOT turned into a cue.
    ///
    /// The intent was "that wall is too busy". Measured, it does not separate: real attempts
    /// against plain walls read 0.11-0.51, and the highest of them is a lighting problem (it
    /// also has the worst cheek imbalance in the set), not a patterned wall. The first threshold
    /// tried here would have nagged 13 of 14 good photos. The reading is kept because it is
    /// cheap and honest, but nothing is said to the user on the strength of it until there is
    /// labelled data showing where the line is.
    public static let busyBackgroundAbove = 0.55

    public static func assess(
        image: PixelImage, luminance: GrayImage, face: FaceMeasurements
    ) -> Reading {
        let samples = wallSamples(luminance: luminance, face: face)
        guard samples.count >= 24 else { return .unusable }

        let mean = samples.reduce(0, +) / Double(samples.count)
        // Spread, not variance: the interquartile range ignores a stray dark hair or highlight
        // while still catching a door frame or a picture on the wall.
        let sorted = samples.sorted()
        let low = sorted[sorted.count / 8]
        let high = sorted[sorted.count - 1 - sorted.count / 8]

        return Reading(
            backgroundBrightness: clamp01(mean),
            backgroundVariation: clamp01(high - low),
            cheekImbalance: ImageMetrics.cheekImbalance(luminance: luminance, face: face),
            isUsable: true
        )
    }

    /// Luminance samples from the wall on each side of the head, at head height.
    static func wallSamples(luminance: GrayImage, face: FaceMeasurements) -> [Double] {
        let width = luminance.width, height = luminance.height
        guard width > 8, height > 8 else { return [] }

        let faceWidth = Double(face.faceWidth)
        let browY = Double(face.browY), chinY = Double(face.rawChin.y)
        // Finite is not enough: these become Int below, and Int(-1e300) traps (LESSONS 32).
        guard faceWidth.isFinite, faceWidth > 1, faceWidth < 1e6,
              abs(browY) < 1e6, abs(chinY) < 1e6, chinY > browY,
              abs(Double(face.contourMinX)) < 1e6,
              abs(Double(face.contourMaxX)) < 1e6 else { return [] }

        // Clear of the hair, which is not wall.
        let margin = 0.35 * faceWidth
        let leftEdge = Double(face.contourMinX) - margin
        let rightEdge = Double(face.contourMaxX) + margin
        guard leftEdge.isFinite, rightEdge.isFinite else { return [] }

        // Beside the head only. Running the band down to the chin dragged in shoulders and
        // clothing, which made 13 of 14 real photos read as "busy wall" - the metric was
        // measuring the person, not the room.
        let faceHeight = chinY - browY
        let top = max(0, min(height - 1, Int((browY - 0.9 * faceHeight).rounded())))
        let bottom = max(0, min(height - 1, Int((browY + 0.35 * faceHeight).rounded())))
        guard bottom > top else { return [] }

        var samples: [Double] = []
        // A fixed budget: this runs several times a second on a live frame.
        let rowStep = max(1, (bottom - top) / 24)
        let columnStep = max(1, width / 64)

        for y in stride(from: top, through: bottom, by: rowStep) {
            for x in stride(from: 0, to: width, by: columnStep) {
                let xd = Double(x)
                guard xd < leftEdge || xd > rightEdge else { continue }
                // GrayImage luminance is on the 0-255 byte scale.
                samples.append(Double(luminance[x, y]) / 255)
            }
        }
        return samples
    }

    static func clamp01(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return Swift.min(1, Swift.max(0, value))
    }
}
