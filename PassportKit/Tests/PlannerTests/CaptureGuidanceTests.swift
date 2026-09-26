import CoreGraphics
import Foundation
import Testing
import TestSupport
import PhotoAnalysis
import PhotoPipeline
import SpecKit

/// The capture coach is pure, so it is tested without a camera.
@Suite("Capture guidance")
struct CaptureGuidanceTests {

    static let frame = CGSize(width: 1080, height: 1920)

    static func spec(_ id: String = "in-passport") throws -> DocumentSpec {
        let name = id == "in-passport" ? "in-passport.json" : "\(id).json"
        return try SpecLoader.load(contentsOf: #require(RepoPaths.specs).appendingPathComponent(name))
    }

    /// A face positioned to satisfy every rule, so individual tests can break one thing.
    static func goodFace(headFraction: Double = 0.60, frame: CGSize = frame) -> FaceMeasurements {
        let head = Double(frame.height) * headFraction
        let centreX = Double(frame.width) / 2
        let crownY = Double(frame.height) * 0.12
        let chinY = crownY + head
        // Brow-to-chin is head / 1.64, matching the estimator the coach falls back to.
        let browY = chinY - head / 1.64
        let eyeY = Double(frame.height) * 0.42
        return FaceMeasurements(
            faceCount: 1,
            boundingBox: CGRect(x: centreX - head / 3, y: crownY, width: head * 0.66, height: head),
            leftEye: CGPoint(x: centreX - head * 0.12, y: eyeY),
            rightEye: CGPoint(x: centreX + head * 0.12, y: eyeY),
            contour: [CGPoint(x: centreX - head / 3, y: eyeY), CGPoint(x: centreX + head / 3, y: eyeY)],
            rawChin: CGPoint(x: centreX, y: chinY),
            browY: CGFloat(browY),
            yawDeg: 0, pitchDeg: 0, rollDeg: 0,
            captureQuality: 0.8, eyeOpenness: 0.30, mouthOpenness: 0.02
        )
    }

    static func assess(
        _ face: FaceMeasurements?, headHeightPx: Double? = nil, cheek: Double? = nil,
        spec: DocumentSpec
    ) -> CaptureAssessment {
        CaptureGuidance.assess(
            face: face, headHeightPx: headHeightPx, cheekImbalance: cheek,
            frameSize: frame, spec: spec
        )
    }

    @Test("an empty frame asks the person to step in")
    func noFace() throws {
        let result = Self.assess(nil, spec: try Self.spec())
        #expect(result.primary?.kind == .noFace)
        #expect(!result.isReady)
    }

    @Test("two people blocks the shutter")
    func twoFaces() throws {
        var face = Self.goodFace()
        face.faceCount = 2
        let result = Self.assess(face, spec: try Self.spec())
        #expect(result.primary?.kind == .tooManyFaces)
        #expect(!result.isReady)
    }

    @Test("a well-placed face is ready")
    func ready() throws {
        let result = Self.assess(Self.goodFace(), spec: try Self.spec())
        #expect(result.isReady, "\(result.cues.map(\.kind.rawValue))")
        #expect(result.primary?.kind == .ready)
    }

    @Test("distance is judged against the spec, and comes first")
    func distance() throws {
        let spec = try Self.spec()
        let band = CaptureGuidance.targetHeadFraction(spec: spec)

        let far = Self.assess(Self.goodFace(headFraction: band.lowerBound - 0.15), spec: spec)
        #expect(far.primary?.kind == .tooFar)

        let close = Self.assess(Self.goodFace(headFraction: band.upperBound + 0.15), spec: spec)
        #expect(close.primary?.kind == .tooClose)
    }

    @Test("each document wants a different distance")
    func distanceDiffersPerSpec() throws {
        let india = CaptureGuidance.targetHeadFraction(spec: try Self.spec("in-passport"))
        let us = CaptureGuidance.targetHeadFraction(spec: try Self.spec("us-passport"))
        // The US head is a smaller share of its square photo, so the person stands further back.
        #expect(us.upperBound < india.lowerBound, "india \(india) us \(us)")
    }

    @Test("move left and move right are not mixed up")
    func centring() throws {
        let spec = try Self.spec()
        var left = Self.goodFace()
        // Face sitting on the left of the frame: the person must move right.
        left.leftEye.x -= Self.frame.width * 0.2
        left.rightEye.x -= Self.frame.width * 0.2
        #expect(Self.assess(left, spec: spec).cues.contains { $0.kind == .offCentre && $0.message == "Move right" })

        var right = Self.goodFace()
        right.leftEye.x += Self.frame.width * 0.2
        right.rightEye.x += Self.frame.width * 0.2
        #expect(Self.assess(right, spec: spec).cues.contains { $0.kind == .offCentre && $0.message == "Move left" })
    }

    /// `y` is top-left pixels, so eyes near the top of the frame mean the camera is too LOW.
    /// These two messages shipped the wrong way round, and there was no test on this branch:
    /// anyone following the spoken cue moved steadily further out of frame.
    @Test("raise and lower the camera are not mixed up")
    func cameraHeight() throws {
        let spec = try Self.spec()

        var high = Self.goodFace()
        let highShift = Self.frame.height * 0.25
        high.leftEye.y -= highShift
        high.rightEye.y -= highShift
        let highCues = Self.assess(high, spec: spec).cues
        #expect(highCues.contains { $0.kind == .tooHigh })
        #expect(highCues.contains { $0.kind == .tooHigh && $0.message == "Raise the camera" })
        #expect(!highCues.contains { $0.message == "Lower the camera" })

        var low = Self.goodFace()
        let lowShift = Self.frame.height * 0.25
        low.leftEye.y += lowShift
        low.rightEye.y += lowShift
        let lowCues = Self.assess(low, spec: spec).cues
        #expect(lowCues.contains { $0.kind == .tooLow })
        #expect(lowCues.contains { $0.kind == .tooLow && $0.message == "Lower the camera" })
        #expect(!lowCues.contains { $0.message == "Raise the camera" })
    }

    @Test("chin up and chin down follow the sign of pitch")
    func pitchDirection() throws {
        let spec = try Self.spec()
        var down = Self.goodFace(); down.pitchDeg = 20
        var up = Self.goodFace(); up.pitchDeg = -20
        #expect(Self.assess(down, spec: spec).cues.contains { $0.kind == .chinDown })
        #expect(Self.assess(up, spec: spec).cues.contains { $0.kind == .chinUp })
    }

    @Test("pose, eyes and mouth all block the shutter")
    func blockingRules() throws {
        let spec = try Self.spec()
        var turned = Self.goodFace(); turned.yawDeg = 20
        var closed = Self.goodFace(); closed.eyeOpenness = 0.05
        var open = Self.goodFace(); open.mouthOpenness = 0.5

        for face in [turned, closed, open] {
            #expect(!Self.assess(face, spec: spec).isReady)
        }
    }

    @Test("lighting advises but never blocks, because a preview frame is not evidence")
    func lightingIsAdvisory() throws {
        let result = Self.assess(Self.goodFace(), cheek: 0.9, spec: try Self.spec())
        let cue = try #require(result.cues.first { $0.kind == .lighting })
        #expect(!cue.isBlocking)
        #expect(result.isReady, "lighting must not stop the shutter")
    }

    @Test("guidance works for every bundled spec")
    func everySpec() throws {
        for id in ["in-passport", "us-passport", "eu-schengen-visa"] {
            let spec = try Self.spec(id)
            let band = CaptureGuidance.targetHeadFraction(spec: spec)
            #expect(band.lowerBound > 0.2 && band.upperBound < 0.9, "\(id) band \(band)")
            let result = Self.assess(Self.goodFace(headFraction: (band.lowerBound + band.upperBound) / 2), spec: spec)
            #expect(result.isReady, "\(id): \(result.cues.map(\.kind.rawValue))")
        }
    }
}

@Suite("Capture stabiliser")
struct CaptureStabiliserTests {

    @Test("one lucky frame does not fire the shutter")
    func needsAStreak() {
        var stabiliser = CaptureStabiliser(requiredFrames: 4)
        var fired: [Bool] = []
        for _ in 0..<4 { fired.append(stabiliser.update(isReady: true)) }
        #expect(fired == [false, false, false, true])
    }

    @Test("a single bad frame resets the streak")
    func resetsOnFailure() {
        var stabiliser = CaptureStabiliser(requiredFrames: 3)
        _ = stabiliser.update(isReady: true)
        _ = stabiliser.update(isReady: true)
        let interrupted = stabiliser.update(isReady: false)
        let progressAfterReset = stabiliser.progress
        #expect(!interrupted)
        #expect(progressAfterReset == 0)

        var fired: [Bool] = []
        for _ in 0..<3 { fired.append(stabiliser.update(isReady: true)) }
        #expect(fired == [false, false, true], "streak must restart from zero")
    }

    @Test("progress climbs towards the shutter")
    func progressClimbs() {
        var stabiliser = CaptureStabiliser(requiredFrames: 4)
        _ = stabiliser.update(isReady: true)
        let quarter = stabiliser.progress
        _ = stabiliser.update(isReady: true)
        let half = stabiliser.progress
        #expect(abs(quarter - 0.25) < 1e-9)
        #expect(abs(half - 0.5) < 1e-9)
    }
}

/// The front camera shows a mirror, so the instruction has to be reversed even though the
/// measurement does not change. Getting this backwards sends people the wrong way.
@Suite("Mirrored guidance")
struct MirroredGuidanceTests {

    @Test("left and right swap on the front camera, and nothing else does")
    func mirroredCentring() throws {
        let spec = try CaptureGuidanceTests.spec()
        var face = CaptureGuidanceTests.goodFace()
        face.leftEye.x -= CaptureGuidanceTests.frame.width * 0.2
        face.rightEye.x -= CaptureGuidanceTests.frame.width * 0.2

        func message(mirrored: Bool) -> String? {
            CaptureGuidance.assess(
                face: face, headHeightPx: nil, cheekImbalance: nil,
                frameSize: CaptureGuidanceTests.frame, spec: spec, isMirrored: mirrored
            ).cues.first { $0.kind == .offCentre }?.message
        }

        #expect(message(mirrored: false) == "Move right")
        #expect(message(mirrored: true) == "Move left")
    }

    @Test("mirroring does not change distance, pose or readiness")
    func mirroringChangesNothingElse() throws {
        let spec = try CaptureGuidanceTests.spec()
        let face = CaptureGuidanceTests.goodFace()
        func assess(_ mirrored: Bool) -> CaptureAssessment {
            CaptureGuidance.assess(
                face: face, headHeightPx: nil, cheekImbalance: nil,
                frameSize: CaptureGuidanceTests.frame, spec: spec, isMirrored: mirrored
            )
        }
        #expect(assess(false).isReady == assess(true).isReady)
        #expect(assess(false).headFraction == assess(true).headFraction)
    }
}
