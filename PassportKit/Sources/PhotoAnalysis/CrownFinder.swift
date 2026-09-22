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

    /// True when the subject already occupies the top edge of the frame, which means the top of
    /// the head is outside the photo.
    ///
    /// `find` cannot tell the difference: on a photo cropped above the hairline it returns row 0
    /// or close to it, and every later measurement then treats that clipped edge as the crown.
    /// The result is an output with the top of the head missing that passes headHeight and
    /// topMargin, because both measure the hair that IS there.
    public static func touchesTopEdge(
        matte: AlphaMatte, face: FaceMeasurements, tuning: Tuning = .default
    ) -> Bool {
        let faceWidth = Double(face.faceWidth)
        guard faceWidth > 0, matte.width > 0, matte.height > 2 else { return false }

        let x0 = max(0, Int((Double(face.contourMinX) - 0.3 * faceWidth).rounded()))
        let x1 = min(matte.width - 1, Int((Double(face.contourMaxX) + 0.3 * faceWidth).rounded()))
        guard x1 > x0 else { return false }

        // A couple of rows, so a single stray pixel on the very edge is not enough.
        let required = tuning.crownSpanFraction * faceWidth
        for y in 0..<min(3, matte.height) {
            var span = 0.0
            for x in x0...x1 where matte[x, y] > 0.5 { span += 1 }
            if span >= required { return true }
        }
        return false
    }
}
