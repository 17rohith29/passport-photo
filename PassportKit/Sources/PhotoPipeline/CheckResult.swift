import Foundation
import SpecKit

public enum CheckID: String, Codable, Sendable, CaseIterable {
    case faceCount, resolution, sharpness, lighting
    case yaw, pitch, roll
    case eyesOpen, mouthClosed
    case dimensions, fileSize
    case headHeight, topMargin, eyeLine, centering, headroom
    case background, faceIntegrity, shouldersVisible
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

    public init(
        id: CheckID, status: CheckStatus, measured: String, requirement: String,
        userMessage: String? = nil, fixability: Fixability = .retakeRequired
    ) {
        self.id = id
        self.status = status
        self.measured = measured
        self.requirement = requirement
        self.userMessage = userMessage
        self.fixability = fixability
    }

    public var isFailure: Bool { status == .fail }
}

public enum Verdict: Sendable, Equatable {
    case meetsRequirements
    case meetsRequirementsWithWarnings
    case cannotUse

    /// Never promises acceptance (CLAUDE.md non-negotiable 6).
    public var headline: String {
        switch self {
        case .meetsRequirements: return "Meets requirements"
        case .meetsRequirementsWithWarnings: return "Meets requirements with warnings"
        case .cannotUse: return "Can't use this photo"
        }
    }

    public static func from(_ checks: [CheckResult]) -> Verdict {
        if checks.contains(where: { $0.status == .fail }) { return .cannotUse }
        if checks.contains(where: { $0.status == .warn }) { return .meetsRequirementsWithWarnings }
        return .meetsRequirements
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
