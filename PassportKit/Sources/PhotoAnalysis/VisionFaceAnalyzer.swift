import CoreGraphics
import Foundation
import Vision

/// Face landmarks, pose and capture quality from Vision's iOS 18 Swift API.
///
/// Vision hands back normalized points with a lower-left origin; `pointsInImageCoordinates`
/// with `.upperLeft` converts straight into PassportKit's pixel space, so no coordinate maths
/// is hand-rolled here (docs/ARCHITECTURE.md).
public struct VisionFaceAnalyzer: FaceAnalyzing {

    public init() {}

    public func analyze(_ image: CGImage) async throws -> FaceMeasurements {
        let landmarksRequest = DetectFaceLandmarksRequest(.revision3)
        let faces = try await landmarksRequest.perform(on: image, orientation: .up)
        guard !faces.isEmpty else { throw FaceAnalysisError.noFaceFound }

        let size = CGSize(width: image.width, height: image.height)
        // Largest face wins; faceCount is reported so the gate can reject group photos.
        let face = faces.max { a, b in
            a.boundingBox.toImageCoordinates(size, origin: .upperLeft).area
                < b.boundingBox.toImageCoordinates(size, origin: .upperLeft).area
        }!

        guard let landmarks = face.landmarks else { throw FaceAnalysisError.landmarksUnavailable }

        func points(_ region: FaceObservation.Landmarks2D.Region) -> [CGPoint] {
            region.pointsInImageCoordinates(size, origin: .upperLeft)
        }

        let contour = points(landmarks.faceContour)
        let leftEyePoints = points(landmarks.leftEye)
        let rightEyePoints = points(landmarks.rightEye)
        guard !contour.isEmpty, !leftEyePoints.isEmpty, !rightEyePoints.isEmpty else {
            throw FaceAnalysisError.landmarksUnavailable
        }

        let leftEye = centroid(leftEyePoints)
        let rightEye = centroid(rightEyePoints)
        // Vision's "left" is the subject's left, which is on the right of the image. Order the
        // pair left-to-right in image space so roll has a consistent sign.
        let (eyeA, eyeB) = leftEye.x <= rightEye.x ? (leftEye, rightEye) : (rightEye, leftEye)

        let brows = points(landmarks.leftEyebrow) + points(landmarks.rightEyebrow)
        let browY = brows.map(\.y).min() ?? eyeA.y

        let rawChin = contour.max { $0.y < $1.y } ?? contour[0]

        let quality = try? await captureQuality(for: image, face: face)

        return FaceMeasurements(
            faceCount: faces.count,
            boundingBox: face.boundingBox.toImageCoordinates(size, origin: .upperLeft),
            leftEye: eyeA,
            rightEye: eyeB,
            contour: contour,
            outerLips: points(landmarks.outerLips),
            innerLips: points(landmarks.innerLips),
            rawChin: rawChin,
            browY: browY,
            yawDeg: face.yaw.converted(to: .degrees).value,
            pitchDeg: face.pitch.converted(to: .degrees).value,
            rollDeg: face.roll.converted(to: .degrees).value,
            captureQuality: quality,
            eyeOpenness: Self.eyeAspectRatio(leftEyePoints, rightEyePoints),
            mouthOpenness: Self.mouthOpenness(
                outer: points(landmarks.outerLips), inner: points(landmarks.innerLips),
                interocular: hypot(eyeB.x - eyeA.x, eyeB.y - eyeA.y)
            )
        )
    }

    private func captureQuality(for image: CGImage, face: FaceObservation) async throws -> Double? {
        var request = DetectFaceCaptureQualityRequest()
        request.inputFaceObservations = [face]
        let results = try await request.perform(on: image, orientation: .up)
        return results.first?.captureQuality.map { Double($0.score) }
    }

    private func centroid(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    /// Eye aspect ratio: height over width. Low means closed. Calibrated on fixtures, not on the
    /// dlib thresholds, because Vision's eye constellation differs from the 68-point model.
    static func eyeAspectRatio(_ left: [CGPoint], _ right: [CGPoint]) -> Double {
        let ratios = [left, right].compactMap(aspectRatio)
        return ratios.min() ?? 0
    }

    private static func aspectRatio(_ points: [CGPoint]) -> Double? {
        guard points.count >= 4 else { return nil }
        let xs = points.map(\.x), ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max(), maxX > minX else { return nil }
        return Double((maxY - minY) / (maxX - minX))
    }

    /// Mouth opening: the inner-lip gap over the interocular distance.
    ///
    /// Normalising by outer-lip WIDTH looked natural but is yaw-sensitive: turning the head
    /// foreshortens the lips horizontally and inflates the ratio, so profile shots scored as
    /// wide-open mouths. Measured on stock portraits, closed mouths landed at 0.081-0.110 by that
    /// method - above the threshold meant to catch parted lips. The interocular distance barely
    /// changes with yaw, so it is the stabler denominator.
    static func mouthOpenness(outer: [CGPoint], inner: [CGPoint], interocular: CGFloat) -> Double {
        guard interocular > 0 else { return 0 }
        guard let top = inner.map(\.y).min(), let bottom = inner.map(\.y).max() else { return 0 }
        _ = outer
        return Double((bottom - top) / interocular)
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}
