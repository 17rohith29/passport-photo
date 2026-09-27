import CoreGraphics
import Foundation
import PhotoAnalysis
import SpecKit

/// One thing to tell the person, right now.
public struct CaptureCue: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable {
        case noFace, tooManyFaces
        case tooFar, tooClose
        case offCentre, tooHigh, tooLow
        case turned, chinUp, chinDown, tilted
        case eyesClosed, mouthOpen
        case lighting
        case darkBackground, busyBackground
        case ready
    }

    public var kind: Kind
    /// Short enough to read at arm's length and to speak aloud.
    public var message: String
    /// Blocking cues stop the shutter; advisory ones do not.
    public var isBlocking: Bool

    public var id: String { kind.rawValue }
}

public struct CaptureAssessment: Sendable, Equatable {
    /// Highest priority first. The UI shows the first, VoiceOver speaks the first.
    public var cues: [CaptureCue]
    public var isReady: Bool
    /// Head height as a fraction of frame height, and the band it should land in, so the UI can
    /// draw a guide that means something rather than a decorative oval.
    public var headFraction: Double
    public var targetHeadFraction: ClosedRange<Double>

    public var primary: CaptureCue? { cues.first }
}

/// Turns a live frame into advice, using the same spec and the same calibration as the import
/// gate, so what the camera asks for is what the gate will accept.
///
/// Pure: no camera, no Vision, no UI. The app feeds it `FaceMeasurements` from a preview frame.
public enum CaptureGuidance {

    /// The head should fill enough of the frame that the passport crop fits inside it with room
    /// for shoulders, but not so much that the crop runs off the top. The crop is
    /// `head / headFraction` tall, so aiming the crop at ~75% of the frame puts the head at
    /// `0.75 * headFraction`, 0.60 for India, 0.44 for the US, 0.56 for Schengen.
    public static func targetHeadFraction(spec: DocumentSpec, tolerance: Double = 0.07)
        -> ClosedRange<Double> {
        let photoHeightMM = spec.photo.sizeMM.height
        let head = spec.geometry.headHeight
        let targetMM = head.targetMM
            ?? HeadHeightBand.inMM(spec: spec).map { ($0.min + $0.max) / 2 }
            ?? photoHeightMM * 0.75
        let headFraction = max(0.1, min(0.95, targetMM / photoHeightMM))
        let centre = 0.75 * headFraction
        // ClosedRange traps when lower > upper, so the tolerance cannot be trusted as given.
        let safe = tolerance.isFinite ? abs(tolerance) : 0.07
        return (centre - safe)...(centre + safe)
    }

    /// `isMirrored` is true for the front camera, whose preview is flipped. The measurement is
    /// unaffected, the face really is on that side of the frame, but the *instruction* must be
    /// reversed, because the person is watching a mirror: moving towards what looks like their
    /// left moves them right in the frame.
    public static func assess(
        face: FaceMeasurements?,
        headHeightPx: Double?,
        cheekImbalance: Double?,
        quality: FrameQuality.Reading? = nil,
        frameSize: CGSize,
        spec: DocumentSpec,
        isMirrored: Bool = false,
        calibration: GateCalibration = .default
    ) -> CaptureAssessment {
        let band = targetHeadFraction(spec: spec)

        guard let face, frameSize.height > 0, frameSize.width > 0 else {
            return CaptureAssessment(
                cues: [CaptureCue(kind: .noFace, message: "Step into the frame", isBlocking: true)],
                isReady: false, headFraction: 0, targetHeadFraction: band
            )
        }

        if face.faceCount > 1 {
            return CaptureAssessment(
                cues: [CaptureCue(kind: .tooManyFaces, message: "Only you in the photo", isBlocking: true)],
                isReady: false, headFraction: 0, targetHeadFraction: band
            )
        }

        // Fall back to a brow-to-chin estimate when the caller has no segmented head height,
        // the same 1.64 factor the import path uses before segmentation.
        let head = headHeightPx ?? Double(face.rawChin.y - face.browY) * 1.64
        let fraction = head / Double(frameSize.height)

        var cues: [CaptureCue] = []

        // Distance first: nothing else is worth fixing until the framing is right.
        if fraction < band.lowerBound {
            cues.append(CaptureCue(kind: .tooFar, message: "Come closer", isBlocking: true))
        } else if fraction > band.upperBound {
            cues.append(CaptureCue(kind: .tooClose, message: "Move back a little", isBlocking: true))
        }

        let centreX = Double(face.eyeMidpoint.x) / Double(frameSize.width)
        if abs(centreX - 0.5) > 0.06 {
            let needsToMoveRight = (centreX < 0.5) != isMirrored
            cues.append(CaptureCue(
                kind: .offCentre,
                message: needsToMoveRight ? "Move right" : "Move left",
                isBlocking: true
            ))
        }

        // Eyes should sit a little above the middle of the frame. `y` is top-left pixels, so a
        // SMALL eyeY means the face sits HIGH in the frame - which is what a camera held too LOW
        // produces, and it is fixed by raising the camera. These two messages were the wrong way
        // round, so anyone following the spoken cue walked themselves out of frame.
        let eyeY = Double(face.eyeMidpoint.y) / Double(frameSize.height)
        if eyeY < 0.30 {
            cues.append(CaptureCue(kind: .tooHigh, message: "Raise the camera", isBlocking: true))
        } else if eyeY > 0.55 {
            cues.append(CaptureCue(kind: .tooLow, message: "Lower the camera", isBlocking: true))
        }

        if let yawLimit = spec.pose?.yawDeg?.failAbove, abs(face.yawDeg) > yawLimit {
            cues.append(CaptureCue(kind: .turned, message: "Face the camera straight on", isBlocking: true))
        }
        if let pitchLimit = spec.pose?.pitchDeg?.failAbove, abs(face.pitchDeg) > pitchLimit {
            cues.append(CaptureCue(
                kind: face.pitchDeg > 0 ? .chinDown : .chinUp,
                message: face.pitchDeg > 0 ? "Lower your chin" : "Lift your chin",
                isBlocking: true
            ))
        }
        if let rollLimit = spec.pose?.rollDeg?.inputFailAbove, abs(face.eyeLineAngleDeg) > rollLimit {
            cues.append(CaptureCue(kind: .tilted, message: "Straighten your head", isBlocking: true))
        }

        if spec.appearance?.eyesOpen == true, face.eyeOpenness < calibration.minEyeOpenness {
            cues.append(CaptureCue(kind: .eyesClosed, message: "Open your eyes", isBlocking: true))
        }
        if spec.appearance?.mouthClosed == true, face.mouthOpenness > calibration.mouthFailAbove {
            cues.append(CaptureCue(kind: .mouthOpen, message: "Close your mouth", isBlocking: true))
        }

        // Lighting is advisory live: it is measured properly on the full-resolution capture, and
        // a preview frame is too small and too noisy to reject someone on.
        // Lighting and background, judged live. Finding out the wall was wrong only after the
        // photo has been taken is the thing this is here to avoid.
        let imbalance = cheekImbalance ?? (quality?.isUsable == true ? quality?.cheekImbalance : nil)
        if let imbalance, let limit = spec.lighting?.cheekImbalance?.failAbove, imbalance > limit {
            cues.append(CaptureCue(
                kind: .lighting, message: "Turn towards the light", isBlocking: false
            ))
        }

        if let quality, quality.isUsable {
            // Advisory, not blocking: the pipeline replaces the background, so a poor wall is not
            // a rejection - it just makes the cut-out worse, which is what produces the mangled
            // edges LESSONS 20 is about. Telling someone to move now costs them nothing.
            if quality.backgroundBrightness < FrameQuality.darkBackgroundBelow {
                cues.append(CaptureCue(
                    kind: .darkBackground,
                    message: "Find a lighter wall behind you", isBlocking: false
                ))
            }
            // No "busy wall" cue: see FrameQuality.busyBackgroundAbove. The metric does not
            // separate a patterned wall from an unevenly lit plain one on real photos, and a
            // cue that fires on a good photo is worse than no cue at all.
        }

        let blocking = cues.contains { $0.isBlocking }
        if !blocking {
            cues.insert(CaptureCue(kind: .ready, message: "Hold still", isBlocking: false), at: 0)
        }

        return CaptureAssessment(
            cues: cues, isReady: !blocking, headFraction: fraction, targetHeadFraction: band
        )
    }
}

/// Decides when a run of ready frames is steady enough to take the photo, so a single lucky
/// frame cannot trigger the shutter.
public struct CaptureStabiliser: Sendable {
    public var requiredFrames: Int
    private var streak = 0

    public init(requiredFrames: Int = 6) {
        self.requiredFrames = requiredFrames
    }

    public var progress: Double {
        requiredFrames > 0 ? min(1, Double(streak) / Double(requiredFrames)) : 0
    }

    /// Returns true on the frame that completes the streak, then resets.
    public mutating func update(isReady: Bool) -> Bool {
        guard isReady else { streak = 0; return false }
        streak += 1
        if streak >= requiredFrames { streak = 0; return true }
        return false
    }

    public mutating func reset() { streak = 0 }
}
