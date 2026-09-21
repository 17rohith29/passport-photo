import Foundation

/// Mirror of `fixtures/expected.json`. Only the fields the suite asserts on are modelled;
/// `pythonReference` is diagnosis-only per that file's `howToAssert`.
struct ExpectedSuite: Codable {
    var specId: String
    var checkIdVocabulary: [String]
    var cases: [ExpectedCase]
}

struct ExpectedCase: Codable {
    enum Expectation: String, Codable { case accept, reject, borderline }

    var file: String
    var expect: Expectation
    var note: String?
    var allowedWarnings: [String]?
    var primaryReasons: [String]?
    var alsoAcceptableReasons: [String]?
    var groundTruth: GroundTruth?
    var output: ExpectedOutput?

    var fileName: String { (file as NSString).lastPathComponent }
}

struct GroundTruth: Codable {
    var imageSizePx: [Double]?
    var orientationApplied: Bool?
    var rollDeg: Measured?
    var crownYPx: Measured?
    var chinYPx: Measured?
    var headHeightPx: Measured?
    var note: String?
}

struct Measured: Codable {
    var value: Double
    var tolerance: Double

    func contains(_ x: Double) -> Bool { abs(x - value) <= tolerance }
}

struct ExpectedOutput: Codable {
    var sizePx: [Double]?
    var fileSizeKB: Bounds?
    var headHeightMM: Bounds?
    var topMarginMM: Bounds?
    var eyeLineFromBottomFraction: Bounds?
    var rollDeg: Bounds?
    var horizontalOffsetFraction: Bounds?
    var backgroundPureFraction: Bounds?
}

struct Bounds: Codable {
    var min: Double?
    var max: Double?

    func contains(_ x: Double) -> Bool {
        if let min, x < min { return false }
        if let max, x > max { return false }
        return true
    }
}
