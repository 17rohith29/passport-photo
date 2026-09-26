import Foundation

/// A decoded `specs/*.json` document. Every country-specific number the app uses lives here,
/// never in Swift. Mirrors `specs/document-spec.schema.json`.
public struct DocumentSpec: Codable, Sendable, Identifiable, Equatable {
    public var schemaVersion: Int
    public var id: String
    public var country: Country
    public var document: Document
    public var status: Status
    public var photo: Photo
    public var geometry: Geometry
    public var pose: Pose?
    public var appearance: Appearance?
    public var lighting: Lighting?
    public var background: Background?
    public var input: Input?
    public var sources: [Source]

    // The schema forbids unknown keys, but "$schema" is a legal pointer the app ignores.
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, country, document, status, photo, geometry
        case pose, appearance, lighting, background, input, sources
    }
}

public struct Country: Codable, Sendable, Equatable {
    public var code: String
    public var name: String
}

public struct Document: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case passport, visa, oci
        case idCard = "id-card"
        case residencePermit = "residence-permit"
        case other
    }
    public var type: Kind
    public var displayName: String
    public var channel: String?
}

public struct Status: Codable, Sendable, Equatable {
    public enum Confidence: String, Codable, Sendable { case high, medium, low }
    public var lastVerified: String
    public var confidence: Confidence
    public var isTestFixture: Bool?
    public var notes: [String]?
    /// Requirements the authority states that the app cannot check. Shown to the user, so a
    /// green verdict is never mistaken for full compliance.
    public var notEnforced: [String]?

    /// Parsed `lastVerified` (yyyy-MM-dd), or nil if it is not a valid date.
    public var lastVerifiedDate: Date? { DateOnly.parse(lastVerified) }
}

public struct Photo: Codable, Sendable, Equatable {
    public var sizeMM: Size
    /// How the size is normally spoken in that country ("2 x 2 in"). Presentation only: never a
    /// geometry input. Every measurement still comes from `sizeMM`.
    public var sizeLabel: String?
    public var digital: Digital
    public var print: PrintSpec
}

public struct Digital: Codable, Sendable, Equatable {
    public enum Format: String, Codable, Sendable { case jpeg }
    public var sizePx: Size?
    public var sizePxRange: SizeRange?
    public var format: Format
    public var fileSizeKB: Range?
    public var dpi: Double?

    /// The pixel size the app renders. A fixed `sizePx` wins; otherwise the largest of a range.
    public var outputSizePx: Size? { sizePx ?? sizePxRange?.max }
}

public struct PrintSpec: Codable, Sendable, Equatable {
    public enum Finish: String, Codable, Sendable { case any, glossy, matte }
    public var dpi: Double
    public var copiesRequired: Int?
    public var paperFinish: Finish?
}

public struct Geometry: Codable, Sendable, Equatable {
    public var headHeight: HeadHeight
    public var topMargin: TopMargin?
    public var eyeLine: EyeLine?
    public var horizontalOffsetFraction: Threshold?
    public var shouldersVisibleFraction: Threshold?
}

public struct HeadHeight: Codable, Sendable, Equatable {
    public enum Measure: String, Codable, Sendable { case chinToCrown }
    public var measure: Measure
    public var targetMM: Double?
    public var passMM: Range?
    public var passFraction: Range?
    public var note: String?
}

public struct TopMargin: Codable, Sendable, Equatable {
    public var targetMM: Double?
    public var passMM: Range?
}

public struct EyeLine: Codable, Sendable, Equatable {
    public var fromBottomFraction: Range?
    public var fromBottomMM: Range?
}

public struct Pose: Codable, Sendable, Equatable {
    public var rollDeg: RollDeg?
    public var yawDeg: Threshold?
    public var pitchDeg: Threshold?
}

public struct RollDeg: Codable, Sendable, Equatable {
    public var inputFailAbove: Double?
    public var outputFailAbove: Double?
}

public struct Appearance: Codable, Sendable, Equatable {
    public enum Expression: String, Codable, Sendable {
        case neutral
        case neutralOrSlightSmile = "neutral-or-slight-smile"
    }
    public var eyesOpen: Bool?
    public var mouthClosed: Bool?
    public var glassesAllowed: Bool?
    public var expression: Expression?
    public var earsVisible: Bool?
}

public struct Lighting: Codable, Sendable, Equatable {
    public var cheekImbalance: Threshold?
}

public struct Background: Codable, Sendable, Equatable {
    /// Whether the authority rules out an edited photo outright, or merely prefers one that is
    /// not edited. `forbidden` makes the app keep the user's own background by default.
    public enum EditingPolicy: String, Codable, Sendable { case forbidden, discouraged }

    public var colorHex: String
    public var pureFraction: Threshold?
    public var minChannelValue: Int?
    public var editingRisk: String?
    public var editingPolicy: EditingPolicy?
}

extension DocumentSpec {
    /// True when this authority rules out an edited photo, so replacing the background would
    /// disqualify it however good the result looks.
    public var forbidsEditing: Bool { background?.editingPolicy == .forbidden }
}

public struct Input: Codable, Sendable, Equatable {
    public var allowUpscaling: Bool?
    public var sharpness: Threshold?
}

public struct Source: Codable, Sendable, Equatable {
    public enum Authority: String, Codable, Sendable {
        case official
        case officialPartner = "official-partner"
        case thirdParty = "third-party"
    }
    public var title: String
    public var url: String
    public var authority: Authority
    public var says: String?
}

// MARK: - Shared value types

public struct Size: Codable, Sendable, Equatable {
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) { self.width = width; self.height = height }
}

public struct SizeRange: Codable, Sendable, Equatable {
    public var min: Size
    public var max: Size
}

public struct Range: Codable, Sendable, Equatable {
    public var min: Double
    public var max: Double
    public init(min: Double, max: Double) { self.min = min; self.max = max }
}

/// Max-type checks use `warnAbove`/`failAbove`; min-type checks use `warnBelow`/`failBelow`.
/// The unit is named by the field that holds the threshold.
public struct Threshold: Codable, Sendable, Equatable {
    public var warnAbove: Double?
    public var failAbove: Double?
    public var warnBelow: Double?
    public var failBelow: Double?
}
