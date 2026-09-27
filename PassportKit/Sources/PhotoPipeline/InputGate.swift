import CoreGraphics
import Foundation
import PhotoAnalysis
import SpecKit

/// Rejects what processing cannot fix, before processing (CLAUDE.md non-negotiable 3).
///
/// Thresholds come from the spec; the calibration constants that turn a Vision measurement into
/// a comparable number live in `GateCalibration`, because Vision's landmarks differ from the
/// dlib 68-point model the Python thresholds were tuned on.
public enum InputGate {

    /// Every authority in the app requires a colour photo, and a greyscale scan otherwise
    /// passes every other check and earns a green verdict.
    ///
    /// The threshold is measured, not guessed: across the fixture photos a colour face reads
    /// 0.39-0.52 and the same photo desaturated reads exactly 0.00. 0.05 sits in a gap so wide
    /// that no realistic colour photo can fall through it.
    public static let minFaceSaturation = 0.05

    public static func colourCheck(_ saturation: Double) -> CheckResult {
        let ok = saturation >= minFaceSaturation
        return CheckResult(
            id: .colour, status: ok ? .pass : .fail,
            measured: ok ? "colour" : "black and white",
            requirement: "colour",
            technical: String(format: "face saturation %.3f, needs %.3f", saturation, minFaceSaturation),
            userMessage: ok ? nil
                : "This photo is black and white, and every passport and visa photo has to be in colour. If you added a black-and-white filter, open the photo in Photos and revert it, or use the original."
        )
    }

    public static func evaluate(
        face: FaceMeasurements,
        sharpness: Double,
        cheekImbalance: Double,
        faceSaturation: Double? = nil,
        headHeightPx: Double,
        imageSize: CGSize,
        spec: DocumentSpec,
        calibration: GateCalibration = .default
    ) -> [CheckResult] {
        var checks: [CheckResult] = []

        checks.append(faceCountCheck(face))
        if let resolution = resolutionCheck(headHeightPx: headHeightPx, spec: spec) {
            checks.append(resolution)
        }
        checks.append(sharpnessCheck(sharpness, spec: spec))
        checks.append(lightingCheck(cheekImbalance, spec: spec))
        if let faceSaturation { checks.append(colourCheck(faceSaturation)) }
        checks.append(yawCheck(face, spec: spec))
        checks.append(pitchCheck(face, spec: spec))
        checks.append(rollCheck(face, spec: spec))
        if spec.appearance?.eyesOpen == true {
            checks.append(eyesOpenCheck(face, calibration: calibration))
        }
        if spec.appearance?.mouthClosed == true {
            checks.append(mouthClosedCheck(face, calibration: calibration))
        }
        return checks
    }

    static func faceCountCheck(_ face: FaceMeasurements) -> CheckResult {
        let ok = face.faceCount == 1
        return CheckResult(
            id: .faceCount,
            status: ok ? .pass : .fail,
            measured: "\(face.faceCount) \(face.faceCount == 1 ? "face" : "faces")",
            requirement: "exactly one face",
            userMessage: ok ? nil : "Use a photo with only you in it.",
            fixability: .retakeRequired
        )
    }

    static func resolutionCheck(headHeightPx: Double, spec: DocumentSpec) -> CheckResult? {
        guard let geometry = SpecGeometry(spec: spec) else { return nil }
        let required = geometry.requiredHeadPx
        let ok = headHeightPx >= required
        let factor = headHeightPx > 0 ? required / headHeightPx : 0
        return CheckResult(
            id: .resolution,
            status: ok ? .pass : .fail,
            measured: String(format: "head is %.0f px tall", headHeightPx),
            requirement: String(format: "at least %.0f px", required),
            userMessage: ok ? nil : String(
                format: "You're too far from the camera. This photo would need %.1fx enlarging, which blurs it. Take one from about 1.5 m with the 2x lens.",
                factor
            ),
            fixability: .retakeRequired
        )
    }

    static func sharpnessCheck(_ value: Double, spec: DocumentSpec) -> CheckResult {
        let threshold = spec.input?.sharpness
        let status = ThresholdEvaluator.evaluateMinimum(value, threshold)
        return CheckResult(
            id: .sharpness,
            status: status,
            measured: status == .pass ? "sharp" : "softer than we can print",
            requirement: "sharp at full size",
            technical: String(format: "sharpness %.0f", value)
                + (threshold?.failBelow.map { String(format: ", needs %.0f", $0) } ?? ""),
            userMessage: status == .pass ? nil : "The photo is blurry. Hold still, or use a photo taken in better light.",
            fixability: .retakeRequired
        )
    }

    static func lightingCheck(_ value: Double, spec: DocumentSpec) -> CheckResult {
        let threshold = spec.lighting?.cheekImbalance
        let status = ThresholdEvaluator.evaluateMaximum(value, threshold)
        return CheckResult(
            id: .lighting,
            status: status,
            measured: String(format: "%.1f%% difference between cheeks", 100 * value),
            requirement: threshold?.failAbove.map { String(format: "under %.0f%%", 100 * $0) } ?? "any",
            userMessage: status == .pass ? nil : "One side of your face is brighter than the other. Turn to face a window or a lamp straight on, then take it again. Processing cannot fix uneven light.",
            fixability: .retakeRequired
        )
    }

    static func yawCheck(_ face: FaceMeasurements, spec: DocumentSpec) -> CheckResult {
        let value = abs(face.yawDeg)
        let threshold = spec.pose?.yawDeg
        let status = ThresholdEvaluator.evaluateMaximum(value, threshold)
        return CheckResult(
            id: .yaw,
            status: status,
            measured: String(format: "turned %.1f°", value),
            requirement: threshold?.failAbove.map { String(format: "under %.0f°", $0) } ?? "any",
            userMessage: status == .pass ? nil : "Look straight at the camera.",
            fixability: .retakeRequired
        )
    }

    static func pitchCheck(_ face: FaceMeasurements, spec: DocumentSpec) -> CheckResult {
        let value = abs(face.pitchDeg)
        let threshold = spec.pose?.pitchDeg
        let status = ThresholdEvaluator.evaluateMaximum(value, threshold)
        return CheckResult(
            id: .pitch,
            status: status,
            measured: String(format: "tilted %.1f° up or down", value),
            requirement: threshold?.failAbove.map { String(format: "under %.0f°", $0) } ?? "any",
            userMessage: status == .pass ? nil : "Keep your chin level and the camera at eye height.",
            fixability: .retakeRequired
        )
    }

    /// Roll is the eye-line angle, not Vision's pose roll, because that is what levelling fixes.
    static func rollCheck(_ face: FaceMeasurements, spec: DocumentSpec) -> CheckResult {
        let value = abs(face.eyeLineAngleDeg)
        let limit = spec.pose?.rollDeg?.inputFailAbove
        let status: CheckStatus = limit.map { value > $0 ? .fail : .pass } ?? .pass
        return CheckResult(
            id: .roll,
            status: status,
            measured: String(format: "head tilted %.1f°", value),
            requirement: limit.map { String(format: "under %.0f° (straightened automatically)", $0) } ?? "any",
            userMessage: status == .pass ? nil : "Your head is tilted too far. Straightening it would crop into your face, so take another with your head level.",
            fixability: status == .pass ? .automatic : .retakeRequired
        )
    }

    static func eyesOpenCheck(_ face: FaceMeasurements, calibration: GateCalibration) -> CheckResult {
        let ok = face.eyeOpenness >= calibration.minEyeOpenness
        return CheckResult(
            id: .eyesOpen,
            status: ok ? .pass : .fail,
            measured: ok ? "open" : "almost shut",
            requirement: "clearly open",
            technical: String(format: "eye openness %.3f, needs %.3f", face.eyeOpenness, calibration.minEyeOpenness),
            userMessage: ok ? nil : "Your eyes look closed. Keep them open and look at the lens.",
            fixability: .retakeRequired
        )
    }

    /// Warn band then fail band, because the measurement cannot separate a closed mouth from
    /// slightly parted lips reliably enough to reject on. See `GateCalibration`.
    static func mouthClosedCheck(_ face: FaceMeasurements, calibration: GateCalibration) -> CheckResult {
        let value = face.mouthOpenness
        let status: CheckStatus
        if value > calibration.mouthFailAbove {
            status = .fail
        } else if value > calibration.mouthWarnAbove {
            status = .warn
        } else {
            status = .pass
        }
        return CheckResult(
            id: .mouthClosed,
            status: status,
            measured: status == .pass ? "closed" : "lips are apart",
            requirement: "closed",
            technical: String(format: "mouth openness %.3f, fails above %.3f", value, calibration.mouthFailAbove),
            userMessage: status == .pass ? nil : (status == .fail
                ? "Close your mouth and keep a neutral expression."
                : "Your lips look slightly apart. A closed, neutral mouth is safest."),
            fixability: .retakeRequired
        )
    }
}

/// Thresholds for measurements that have no published number and had to be calibrated on the
/// fixture set. Kept apart from `Tuning` because these are gate decisions, not algorithm knobs,
/// and apart from `specs/` because they describe Vision's scale, not a country's rules.
public struct GateCalibration: Sendable, Equatable {
    /// Vision eye aspect ratio. Fixtures span 0.227-0.310 with no closed eyes, so this sits
    /// below the observed floor and only catches genuinely shut eyes.
    public var minEyeOpenness: Double = 0.18

    /// Inner-lip gap over interocular distance, warn band then fail band.
    ///
    /// Measured on 17 third-party portraits as well as the owner's fixtures, the two populations
    /// OVERLAP: mouths that are visibly closed read as high as 0.096 (including a frontal one at
    /// 0.077), while the owner's parted-lip IMG_0009 reads 0.062. No single threshold separates
    /// them, so a hard reject at 0.07 would have turned away real users with closed mouths -
    /// 12 of those 17 portraits.
    ///
    /// Clearly-open mouths are separable: they start at 0.156, well clear of 0.096. So the fail
    /// band sits at 0.13, in that gap, and everything in between only warns.
    public var mouthWarnAbove: Double = 0.050
    public var mouthFailAbove: Double = 0.130

    public static let `default` = GateCalibration()

    public init() {}
}
