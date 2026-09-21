import CoreGraphics
import Foundation
import PhotoAnalysis

/// Rotates the photo about the eye midpoint so the eye line is horizontal.
///
/// Uses the eye-line angle, not Vision's pose roll — see `FaceMeasurements.eyeLineAngleDeg`.
/// The canvas keeps the source size; edges that rotate in are filled with the nearest edge
/// pixel so the crop never sees transparent corners.
public enum Leveler {

    public static func level(_ image: CGImage, byDegrees degrees: Double, about pivot: CGPoint) -> CGImage? {
        guard abs(degrees) > 0.01 else { return image }

        let width = image.width, height = image.height
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info
        ) else { return nil }

        context.interpolationQuality = .high
        // Fill first so any area rotated in from outside is neutral rather than transparent.
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // CGContext is bottom-left; the pivot arrives in top-left pixel space.
        let pivotY = CGFloat(height) - pivot.y
        context.translateBy(x: pivot.x, y: pivotY)
        // The eye-line angle is measured in top-left space, where positive tips the right eye
        // down. Undoing it means rotating the other way there, which is *positive* in
        // CGContext's y-up frame. Negating here rotated the wrong way and doubled the tilt:
        // IMG_0012 went in at 1.8 deg and came out at 3.8.
        context.rotate(by: CGFloat(degrees * .pi / 180))
        context.translateBy(x: -pivot.x, y: -pivotY)

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
