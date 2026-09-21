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

    public static func evaluate(
        face: FaceMeasurements,
        sharpness: Double,
        cheekImbalance: Double,
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
                format: "You're too far from the camera — this photo would need %.1fx enlarging, which blurs it. Take one from about 1.5 m with the 2x lens.",
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
            measured: String(format: "%.0f", value),
            requirement: threshold?.failBelow.map { String(format: "at least %.0f", $0) } ?? "any",
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
            userMessage: status == .pass ? nil : "One side of your face is brighter than the other. Face a window or a lamp straight on — processing can't fix this.",
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
            userMessage: status == .pass ? nil : "Your head is tilted too far to straighten without cropping badly.",
            fixability: status == .pass ? .automatic : .retakeRequired
        )
    }

    static func eyesOpenCheck(_ face: FaceMeasurements, calibration: GateCalibration) -> CheckResult {
        let ok = face.eyeOpenness >= calibration.minEyeOpenness
        return CheckResult(
            id: .eyesOpen,
            status: ok ? .pass : .fail,
            measured: String(format: "%.3f", face.eyeOpenness),
            requirement: String(format: "at least %.3f", calibration.minEyeOpenness),
            userMessage: ok ? nil : "Your eyes look closed. Keep them open and look at the lens.",
            fixability: .retakeRequired
        )
    }

    static func mouthClosedCheck(_ face: FaceMeasurements, calibration: GateCalibration) -> CheckResult {
        let ok = face.mouthOpenness <= calibration.maxMouthOpenness
        return CheckResult(
            id: .mouthClosed,
            status: ok ? .pass : .fail,
            measured: String(format: "%.3f", face.mouthOpenness),
            requirement: String(format: "at most %.3f", calibration.maxMouthOpenness),
            userMessage: ok ? nil : "Close your mouth and keep a neutral expression.",
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

    /// Vision inner-lip height over outer-lip width. IMG_0009 (lips parted, a required rejection)
    /// measures 0.083; the next highest fixture is IMG_0016 at 0.059. 0.070 splits them.
    public var maxMouthOpenness: Double = 0.070

    public static let `default` = GateCalibration()

    public init() {}
}
