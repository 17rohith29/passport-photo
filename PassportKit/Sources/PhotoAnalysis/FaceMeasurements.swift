import CoreGraphics
import Foundation

/// Everything the pipeline needs from a face, in top-left pixel coordinates on the oriented image.
public struct FaceMeasurements: Sendable, Equatable {
    public var faceCount: Int
    public var boundingBox: CGRect
    public var leftEye: CGPoint
    public var rightEye: CGPoint
    public var contour: [CGPoint]
    /// Lowest contour point, before `ChinRefiner` walks into the beard.
    public var rawChin: CGPoint
    public var browY: CGFloat
    public var yawDeg: Double
    public var pitchDeg: Double
    public var rollDeg: Double
    public var captureQuality: Double?
    public var eyeOpenness: Double
    public var mouthOpenness: Double

    public init(
        faceCount: Int, boundingBox: CGRect, leftEye: CGPoint, rightEye: CGPoint,
        contour: [CGPoint], rawChin: CGPoint, browY: CGFloat,
        yawDeg: Double, pitchDeg: Double, rollDeg: Double,
        captureQuality: Double?, eyeOpenness: Double, mouthOpenness: Double
    ) {
        self.faceCount = faceCount
        self.boundingBox = boundingBox
        self.leftEye = leftEye
        self.rightEye = rightEye
        self.contour = contour
        self.rawChin = rawChin
        self.browY = browY
        self.yawDeg = yawDeg
        self.pitchDeg = pitchDeg
        self.rollDeg = rollDeg
        self.captureQuality = captureQuality
        self.eyeOpenness = eyeOpenness
        self.mouthOpenness = mouthOpenness
    }

    public var eyeMidpoint: CGPoint {
        CGPoint(x: (leftEye.x + rightEye.x) / 2, y: (leftEye.y + rightEye.y) / 2)
    }

    /// Angle of the line between the eyes, in degrees, positive clockwise in top-left space.
    ///
    /// This — not `rollDeg` — is what the Leveler zeroes and what the output roll check measures.
    /// Vision's `rollDeg` is a 3D head-pose estimate and is a different quantity: on IMG_0012 it
    /// reads -5.98 deg while the eye line is 1.84 deg, and levelling by the pose value would
    /// visibly over-rotate the photo.
    public var eyeLineAngleDeg: Double {
        Double(atan2(rightEye.y - leftEye.y, rightEye.x - leftEye.x)) * 180 / .pi
    }

    public var interocularDistance: CGFloat {
        hypot(rightEye.x - leftEye.x, rightEye.y - leftEye.y)
    }

    /// Face width from the contour extremes, in pixels.
    public var faceWidth: CGFloat {
        guard let minX = contour.map(\.x).min(), let maxX = contour.map(\.x).max() else {
            return boundingBox.width
        }
        return maxX - minX
    }

    public var contourMinX: CGFloat { contour.map(\.x).min() ?? boundingBox.minX }
    public var contourMaxX: CGFloat { contour.map(\.x).max() ?? boundingBox.maxX }

    /// The same face expressed in a resized copy of the image. Segmentation and matte refinement
    /// run at a reduced working resolution, and need the landmarks in that space.
    public func scaled(by factor: Double) -> FaceMeasurements {
        let f = CGFloat(factor)
        func scale(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x * f, y: point.y * f) }
        var copy = self
        copy.boundingBox = boundingBox.applying(CGAffineTransform(scaleX: f, y: f))
        copy.leftEye = scale(leftEye)
        copy.rightEye = scale(rightEye)
        copy.contour = contour.map(scale)
        copy.rawChin = scale(rawChin)
        copy.browY = browY * f
        return copy
    }
}

public protocol FaceAnalyzing: Sendable {
    func analyze(_ image: CGImage) async throws -> FaceMeasurements
}

public enum FaceAnalysisError: Error, CustomStringConvertible, Equatable {
    case noFaceFound
    case multipleFaces(Int)
    case landmarksUnavailable

    public var description: String {
        switch self {
        case .noFaceFound: return "No face was found in the photo."
        case let .multipleFaces(count): return "Found \(count) faces; the photo must contain exactly one."
        case .landmarksUnavailable: return "Vision returned a face without landmarks."
        }
    }
}
