import CoreGraphics
import Foundation
import Testing
import TestSupport
@testable import SpecKit

/// Swift traps rather than throws on a bad numeric conversion, a negative buffer size or an
/// inverted range, those kill the app, they do not surface as errors. Every value here reaches
/// such a site, and every case in this suite would have crashed the test process before the
/// guards went in.
@Suite("Crash safety: specs")
struct SpecCrashSafetyTests {

    /// `background.minChannelValue` is converted straight to `UInt8` when a finished photo is
    /// checked. The JSON schema bounds it 0-255; `Codable` does not enforce that, so a country
    /// file could crash the app.
    @Test("a minChannelValue outside 0-255 is rejected, not converted")
    func minChannelValueBounds() {
        for value in [-1, 256, 300, 99999, -99999] {
            let json = SpecValidationTests.validJSON(
                background: ##"{ "colorHex": "#FFFFFF", "minChannelValue": \##(value) }"##
                    .replacingOccurrences(of: "\\\(value)", with: "\(value)")
            )
            #expect(throws: SpecLoadError.self) { try SpecLoader.load(data: json) }
        }
    }

    @Test("a valid minChannelValue still loads")
    func minChannelValueAccepted() throws {
        for value in [0, 128, 245, 255] {
            let json = SpecValidationTests.validJSON(
                background: "{ \"colorHex\": \"#FFFFFF\", \"minChannelValue\": \(value) }"
            )
            _ = try SpecLoader.load(data: json)
        }
    }

    @Test("a zero or negative photo size is rejected before it reaches the geometry")
    func photoSizeMustBePositive() throws {
        var object = try #require(
            try JSONSerialization.jsonObject(with: SpecValidationTests.validJSON()) as? [String: Any]
        )
        var photo = try #require(object["photo"] as? [String: Any])
        for bad in [0, -51] {
            photo["sizeMM"] = ["width": bad, "height": 51]
            object["photo"] = photo
            let data = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: SpecLoadError.self) { try SpecLoader.load(data: data) }
        }
    }

    @Test("a zero pixel size is rejected, so no buffer is ever sized from it")
    func pixelSizeMustBePositive() throws {
        let json = SpecValidationTests.validJSON(
            digital: #"{ "sizePx": { "width": 0, "height": 600 }, "format": "jpeg" }"#
        )
        #expect(throws: SpecLoadError.self) { try SpecLoader.load(data: json) }
    }

    @Test("a head taller than the photo is rejected")
    func headMustFitThePhoto() {
        let json = SpecValidationTests.validJSON(
            headHeight: #"{ "measure": "chinToCrown", "passMM": { "min": 25, "max": 400 } }"#
        )
        #expect(throws: SpecLoadError.self) { try SpecLoader.load(data: json) }
    }

    @Test("a head fraction outside 0-1 is rejected")
    func headFractionBounds() {
        let json = SpecValidationTests.validJSON(
            headHeight: #"{ "measure": "chinToCrown", "passFraction": { "min": 0.7, "max": 1.6 } }"#
        )
        #expect(throws: SpecLoadError.self) { try SpecLoader.load(data: json) }
    }

    @Test("zero copies is rejected")
    func copiesMustBePositive() throws {
        var object = try #require(
            try JSONSerialization.jsonObject(with: SpecValidationTests.validJSON()) as? [String: Any]
        )
        var photo = try #require(object["photo"] as? [String: Any])
        photo["print"] = ["dpi": 300, "copiesRequired": 0]
        object["photo"] = photo
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: SpecLoadError.self) { try SpecLoader.load(data: data) }
    }

    @Test("every shipped spec passes the new bounds")
    func shippedSpecsStillLoad() throws {
        let root = try #require(RepoPaths.specs)
        let urls = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? [])
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != "document-spec.schema.json" }
        #expect(urls.count >= 3)
        for url in urls {
            _ = try SpecLoader.load(contentsOf: url)
        }
    }
}
