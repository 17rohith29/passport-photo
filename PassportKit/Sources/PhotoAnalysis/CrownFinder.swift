import CoreGraphics
import Foundation

/// Top of the hair mass.
///
/// LESSONS 2: taking the first mask pixel makes the head measure taller than it is, because
/// stray strands sit about 0.2 mm above the hair. The crown is the first row where the subject
/// spans at least `crownSpanFraction` of face width.
public enum CrownFinder {

    public static func find(
        matte: AlphaMatte, face: FaceMeasurements, tuning: Tuning = .default
    ) -> CGFloat? {
        let faceWidth = Double(face.faceWidth)
        guard faceWidth > 0, matte.width > 0, matte.height > 0 else { return nil }

        // Search a column window around the face, so a raised hand or shoulder cannot qualify.
        let x0 = max(0, Int((Double(face.contourMinX) - 0.3 * faceWidth).rounded()))
        let x1 = min(matte.width - 1, Int((Double(face.contourMaxX) + 0.3 * faceWidth).rounded()))
        guard x1 > x0 else { return nil }

        let required = tuning.crownSpanFraction * faceWidth
        let lastRow = min(matte.height - 1, Int(face.rawChin.y.rounded()))

        for y in 0...lastRow {
            var span = 0.0
            for x in x0...x1 where matte[x, y] > 0.5 { span += 1 }
            if span >= required { return CGFloat(y) }
        }
        return nil
    }
}
