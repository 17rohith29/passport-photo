import Foundation
import SpecKit

public enum CheckID: String, Codable, Sendable, CaseIterable {
    case faceCount, resolution, sharpness, lighting
    case yaw, pitch, roll
    case eyesOpen, mouthClosed
    case dimensions, fileSize
    case headHeight, topMargin, eyeLine, centering, headroom
    case background, faceIntegrity, shouldersVisible
    case colour
    /// Whether the finished photo counts as unedited. Replacing the background is an edit, and
    /// several authorities reject edited photos outright.
    case unedited
}

public enum CheckStatus: String, Codable, Sendable {
    case pass, warn, fail
}

public enum Fixability: String, Codable, Sendable {
    /// Processing handles it; the user does not need to do anything.
    case automatic
    /// No amount of processing fixes this. The user has to take another photo.
    case retakeRequired
}

/// One requirement, measured. Every rejection says what was measured, what was required and
/// what to do about it (CLAUDE.md non-negotiable 3).
public struct CheckResult: Sendable, Identifiable, Equatable {
    public var id: CheckID
    public var status: CheckStatus
    public var measured: String
    public var requirement: String
    public var userMessage: String?
    public var fixability: Fixability
    /// The raw figure behind `measured`, for the full checks list. Kept out of `measured` so a
    /// rejection reads as a sentence rather than as telemetry: "0.171 / 0.180" tells a person
    /// nothing except that a machine judged them by a rule they cannot see.
    public var technical: String?

    public init(
        id: CheckID, status: CheckStatus, measured: String, requirement: String,
        technical: String? = nil,
        userMessage: String? = nil, fixability: Fixability = .retakeRequired
    ) {
        self.id = id
        self.status = status
        self.measured = measured
        self.requirement = requirement
        self.userMessage = userMessage
        self.fixability = fixability
        self.technical = technical
    }

    public var isFailure: Bool { status == .fail }
}

public enum Verdict: Sendable, Equatable {
    case inRange
    case inRangeWithWarnings
    case cannotUse

    /// Speaks only for what was measured (CLAUDE.md non-negotiable 6).
    ///
    /// This used to read "Meets requirements", which claimed more than the app can know. The app
    /// measures a handful of things it can measure; it cannot see how old the photo is, whether
    /// glasses are being worn, or what it will be printed on, and it says so on the same screen.
    /// A headline asserting the requirements are met, sitting directly above a warning that the
    /// photo breaks one of them, is a contradiction however carefully the warning is worded.
    public var headline: String {
        switch self {
        case .inRange: return "Measurements are in range"
        case .inRangeWithWarnings: return "In range, with warnings"
        case .cannotUse: return "Can't use this photo"
        }
    }

    public static func from(_ checks: [CheckResult]) -> Verdict {
        if checks.contains(where: { $0.status == .fail }) { return .cannotUse }
        if checks.contains(where: { $0.status == .warn }) { return .inRangeWithWarnings }
        return .inRange
    }
}

/// Applies a spec threshold to a measured value and says pass / warn / fail.
public enum ThresholdEvaluator {
    public static func evaluateMaximum(_ value: Double, _ threshold: Threshold?) -> CheckStatus {
        guard let threshold else { return .pass }
        if let fail = threshold.failAbove, value > fail { return .fail }
        if let warn = threshold.warnAbove, value > warn { return .warn }
        return .pass
    }

    public static func evaluateMinimum(_ value: Double, _ threshold: Threshold?) -> CheckStatus {
        guard let threshold else { return .pass }
        if let fail = threshold.failBelow, value < fail { return .fail }
        if let warn = threshold.warnBelow, value < warn { return .warn }
        return .pass
    }

    public static func evaluateRange(_ value: Double, _ range: SpecKit.Range?) -> CheckStatus {
        guard let range else { return .pass }
        return (value >= range.min && value <= range.max) ? .pass : .fail
    }
}
