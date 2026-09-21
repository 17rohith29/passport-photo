import CoreGraphics
import Foundation
import SpecKit

public struct CropPlan: Equatable, Sendable {
    /// Crop rectangle in levelled source pixels, top-left origin.
    public var rect: CGRect
    public var outputSize: CGSize
    /// Source px per output px. Below 1 would mean upscaling, which is never allowed.
    public var scale: Double

    public init(rect: CGRect, outputSize: CGSize, scale: Double) {
        self.rect = rect
        self.outputSize = outputSize
        self.scale = scale
    }
}

public enum PlanError: Error, CustomStringConvertible, Equatable {
    case headTooSmall(measured: Double, required: Double)
    case missingGeometry(String)
    case degenerate

    public var description: String {
        switch self {
        case let .headTooSmall(measured, required):
            let factor = measured > 0 ? required / measured : 0
            return String(
                format: "The head is %.0f px tall but needs %.0f px; that would mean %.2fx upscaling.",
                measured, required, factor
            )
        case let .missingGeometry(field): return "The spec is missing \(field)."
        case .degenerate: return "The crop worked out to nothing."
        }
    }
}

/// Resolves the head-height band to millimetres, whichever way the spec states it.
public enum HeadHeightBand {
    public static func inMM(spec: DocumentSpec) -> SpecKit.Range? {
        let head = spec.geometry.headHeight
        if let mm = head.passMM { return mm }
        if let fraction = head.passFraction {
            let height = spec.photo.sizeMM.height
            return SpecKit.Range(min: fraction.min * height, max: fraction.max * height)
        }
        return nil
    }
}

/// Pure geometry: where to cut the photo so the head lands at the spec's size and position.
///
/// Ported from the crop maths in `reference/python/auto_passport.py`: aim for the target top
/// margin first, then move off it only as far as needed to keep the eye line inside its band.
public enum CropPlanner {

    public static func plan(
        crown: CGFloat, chin: CGFloat, eyes: (CGPoint, CGPoint),
        imageSize: CGSize, spec: DocumentSpec
    ) -> Result<CropPlan, PlanError> {
        guard let geometry = SpecGeometry(spec: spec) else {
            return .failure(.missingGeometry("photo.digital size"))
        }
        let headPx = Double(chin - crown)
        guard headPx > 0, imageSize.width > 0, imageSize.height > 0 else {
            return .failure(.degenerate)
        }

        // Never upscale (LESSONS 3).
        if headPx < geometry.requiredHeadPx {
            return .failure(.headTooSmall(measured: headPx, required: geometry.requiredHeadPx))
        }

        let photoHeightMM = spec.photo.sizeMM.height
        let photoWidthMM = spec.photo.sizeMM.width
        let head = spec.geometry.headHeight
        guard let targetHeadMM = head.targetMM
            ?? head.passMM.map({ ($0.min + $0.max) / 2 })
            ?? head.passFraction.map({ ($0.min + $0.max) / 2 * photoHeightMM })
        else {
            return .failure(.missingGeometry("geometry.headHeight target"))
        }

        // Crop height follows from the head filling targetHeadMM of the photo height.
        let headFraction = targetHeadMM / photoHeightMM
        let cropHeight = headPx / headFraction
        let cropWidth = cropHeight * photoWidthMM / photoHeightMM

        // Where the eyes sit within the head, so the eye-line band can be honoured.
        let eyeY = Double((eyes.0.y + eyes.1.y) / 2)
        let eyeWithinHead = (eyeY - Double(crown)) / headPx

        var topFraction = (spec.geometry.topMargin?.targetMM ?? 0.05 * photoHeightMM) / photoHeightMM
        let eyeFromBottom = 1 - topFraction - eyeWithinHead * headFraction

        if let band = eyeLineBand(spec: spec, photoHeightMM: photoHeightMM) {
            let margin = 0.01
            if eyeFromBottom < band.min + margin {
                topFraction = 1 - (band.min + margin) - eyeWithinHead * headFraction
            }
            if eyeFromBottom > band.max - margin {
                topFraction = 1 - (band.max - margin) - eyeWithinHead * headFraction
            }
        }

        // Keep the top margin inside its own band, just inside the limits.
        if let topBand = spec.geometry.topMargin?.passMM {
            let low = topBand.min / photoHeightMM
            let high = topBand.max / photoHeightMM
            let inset = 0.004
            topFraction = Swift.min(Swift.max(topFraction, low + inset), high - inset)
        }
        topFraction = Swift.max(topFraction, 0)

        let centreX = Double((eyes.0.x + eyes.1.x) / 2)
        let top = Double(crown) - topFraction * cropHeight
        let rect = CGRect(
            x: centreX - cropWidth / 2, y: top,
            width: cropWidth, height: cropHeight
        )

        let outputSize = CGSize(
            width: geometry.outputSizePx.width, height: geometry.outputSizePx.height
        )
        let scale = cropHeight / outputSize.height
        return .success(CropPlan(rect: rect, outputSize: outputSize, scale: scale))
    }

    /// The eye-line band as a fraction of photo height, whichever way the spec states it.
    public static func eyeLineBand(spec: DocumentSpec, photoHeightMM: Double) -> SpecKit.Range? {
        guard let eyeLine = spec.geometry.eyeLine else { return nil }
        if let fraction = eyeLine.fromBottomFraction { return fraction }
        if let mm = eyeLine.fromBottomMM {
            return SpecKit.Range(min: mm.min / photoHeightMM, max: mm.max / photoHeightMM)
        }
        return nil
    }
}
