import Foundation
import Testing
import TestSupport
@testable import SpecKit

@Suite("Decoding real specs")
struct DocumentSpecDecodingTests {

    @Test("in-passport.json decodes with the values the pipeline relies on")
    func decodesIndiaPassport() throws {
        let url = try #require(RepoPaths.inPassportSpec)
        let spec = try SpecLoader.load(contentsOf: url)

        #expect(spec.id == "in-passport")
        #expect(spec.schemaVersion == 1)
        #expect(spec.country.code == "IN")
        #expect(spec.document.type == .passport)
        #expect(spec.status.confidence == .medium)
        #expect(spec.status.lastVerifiedDate != nil)
        #expect(spec.status.isTestFixture == nil)

        #expect(spec.photo.sizeMM == Size(width: 35, height: 45))
        #expect(spec.photo.digital.sizePx == Size(width: 630, height: 810))
        #expect(spec.photo.digital.format == .jpeg)
        #expect(spec.photo.digital.fileSizeKB == Range(min: 10, max: 250))
        #expect(spec.photo.print.dpi == 300)

        #expect(spec.geometry.headHeight.measure == .chinToCrown)
        // 34 mm, ICAO's midpoint: India's own booklet publishes no head figure at all.
        #expect(spec.geometry.headHeight.targetMM == 34.0)
        #expect(spec.geometry.headHeight.passMM == Range(min: 32.0, max: 36.0))
        #expect(spec.geometry.eyeLine?.fromBottomFraction == Range(min: 0.50, max: 0.60))
        #expect(spec.geometry.horizontalOffsetFraction?.failAbove == 0.02)
        #expect(spec.geometry.shouldersVisibleFraction?.failBelow == 0.60)

        #expect(spec.pose?.rollDeg?.inputFailAbove == 10)
        #expect(spec.pose?.rollDeg?.outputFailAbove == 2)
        #expect(spec.pose?.yawDeg?.warnAbove == 5)
        #expect(spec.pose?.yawDeg?.failAbove == 8)

        #expect(spec.appearance?.glassesAllowed == false)
        #expect(spec.appearance?.expression == .neutral)
        #expect(spec.lighting?.cheekImbalance?.warnAbove == 0.08)
        #expect(spec.lighting?.cheekImbalance?.failAbove == 0.12)
        #expect(spec.background?.colorHex == "#FFFFFF")
        #expect(spec.background?.minChannelValue == 245)
        #expect(spec.input?.allowUpscaling == false)
        #expect(spec.input?.sharpness?.failBelow == 100)
        #expect(spec.sources.count >= 1)
        #expect(spec.sources.contains { $0.authority == .officialPartner })
    }

    @Test("the fake square spec decodes, including sizePxRange and a mm eye line")
    func decodesSquareFixture() throws {
        let url = try #require(RepoPaths.squareTestSpec)
        let spec = try SpecLoader.load(contentsOf: url)

        #expect(spec.id == "test-square")
        #expect(spec.status.isTestFixture == true)
        #expect(spec.document.type == .other)
        #expect(spec.photo.sizeMM == Size(width: 51, height: 51))
        #expect(spec.photo.digital.sizePx == nil)
        #expect(spec.photo.digital.sizePxRange?.min == Size(width: 600, height: 600))
        #expect(spec.photo.digital.sizePxRange?.max == Size(width: 1200, height: 1200))
        #expect(spec.geometry.headHeight.targetMM == nil)
        #expect(spec.geometry.headHeight.passMM == Range(min: 25, max: 35))
        #expect(spec.geometry.eyeLine?.fromBottomMM == Range(min: 28, max: 35))
        #expect(spec.geometry.eyeLine?.fromBottomFraction == nil)
    }

    @Test("a test-fixture spec is flagged so it is never shown to users")
    func testFixtureIsFlagged() throws {
        let real = try SpecLoader.load(contentsOf: #require(RepoPaths.inPassportSpec))
        let fake = try SpecLoader.load(contentsOf: #require(RepoPaths.squareTestSpec))
        #expect(real.status.isTestFixture != true)
        #expect(fake.status.isTestFixture == true)
    }
}

@Suite("Spec validation")
struct SpecValidationTests {

    /// A minimal valid spec, mutated per test so each case isolates one rule.
    static func validJSON(
        schemaVersion: String = "1",
        id: String = "zz-test",
        countryCode: String = "ZZ",
        lastVerified: String = "2026-09-20",
        digital: String = #"{ "sizePx": { "width": 600, "height": 600 }, "format": "jpeg" }"#,
        headHeight: String = #"{ "measure": "chinToCrown", "passMM": { "min": 25, "max": 35 } }"#,
        background: String = ##"{ "colorHex": "#FFFFFF" }"##,
        sources: String = #"[{ "title": "t", "url": "about:blank", "authority": "third-party" }]"#
    ) -> Data {
        Data("""
        {
          "schemaVersion": \(schemaVersion),
          "id": "\(id)",
          "country": { "code": "\(countryCode)", "name": "Testland" },
          "document": { "type": "other", "displayName": "Test" },
          "status": { "lastVerified": "\(lastVerified)", "confidence": "low" },
          "photo": {
            "sizeMM": { "width": 51, "height": 51 },
            "digital": \(digital),
            "print": { "dpi": 300 }
          },
          "geometry": { "headHeight": \(headHeight) },
          "background": \(background),
          "sources": \(sources)
        }
        """.utf8)
    }

    @Test("the baseline test spec is valid")
    func baselineIsValid() throws {
        _ = try SpecLoader.load(data: Self.validJSON())
    }

    @Test("a missing required field names the field")
    func missingFieldIsReadable() {
        let json = Data(#"{ "schemaVersion": 1, "id": "zz-test" }"#.utf8)
        #expect(throws: SpecLoadError.self) { try SpecLoader.load(data: json) }
        do {
            _ = try SpecLoader.load(data: json)
        } catch let error as SpecLoadError {
            #expect("\(error)".contains("country"))
            #expect("\(error)".contains("missing required field"))
        } catch {
            Issue.record("expected SpecLoadError, got \(error)")
        }
    }

    @Test("an unknown enum value is reported, not silently dropped")
    func unknownEnumIsRejected() {
        let json = Self.validJSON(background: ##"{ "colorHex": "#FFFFFF" }"##)
        var object = try! JSONSerialization.jsonObject(with: json) as! [String: Any]
        object["document"] = ["type": "hovercraft-licence", "displayName": "Nope"]
        let mutated = try! JSONSerialization.data(withJSONObject: object)
        #expect(throws: SpecLoadError.self) { try SpecLoader.load(data: mutated) }
    }

    @Test("schemaVersion must be 1")
    func wrongSchemaVersion() {
        #expect(throws: SpecLoadError.self) {
            try SpecLoader.load(data: Self.validJSON(schemaVersion: "2"))
        }
    }

    @Test("id and country code are format-checked")
    func badIdentifiers() {
        #expect(throws: SpecLoadError.self) { try SpecLoader.load(data: Self.validJSON(id: "ZZ Test")) }
        #expect(throws: SpecLoadError.self) { try SpecLoader.load(data: Self.validJSON(countryCode: "zz")) }
        #expect(throws: SpecLoadError.self) { try SpecLoader.load(data: Self.validJSON(countryCode: "ZZZ")) }
    }

    @Test("lastVerified must be a real yyyy-MM-dd date")
    func badDate() {
        #expect(throws: SpecLoadError.self) { try SpecLoader.load(data: Self.validJSON(lastVerified: "20 Sep 2026")) }
        #expect(throws: SpecLoadError.self) { try SpecLoader.load(data: Self.validJSON(lastVerified: "2026-13-40")) }
    }

    @Test("digital must have exactly one of sizePx / sizePxRange")
    func digitalSizeExclusivity() {
        let neither = #"{ "format": "jpeg" }"#
        let both = """
        { "sizePx": { "width": 600, "height": 600 },
          "sizePxRange": { "min": { "width": 600, "height": 600 }, "max": { "width": 1200, "height": 1200 } },
          "format": "jpeg" }
        """
        #expect(throws: SpecLoadError.self) { try SpecLoader.load(data: Self.validJSON(digital: neither)) }
        #expect(throws: SpecLoadError.self) { try SpecLoader.load(data: Self.validJSON(digital: both)) }
    }

    @Test("headHeight needs passMM or passFraction")
    func headHeightNeedsABand() {
        let bare = #"{ "measure": "chinToCrown", "targetMM": 36 }"#
        #expect(throws: SpecLoadError.self) { try SpecLoader.load(data: Self.validJSON(headHeight: bare)) }
    }

    @Test("an inverted range is rejected")
    func invertedRange() {
        let inverted = #"{ "measure": "chinToCrown", "passMM": { "min": 35, "max": 25 } }"#
        #expect(throws: SpecLoadError.self) { try SpecLoader.load(data: Self.validJSON(headHeight: inverted)) }
    }

    @Test("background colour must be #RRGGBB")
    func badColour() {
        #expect(throws: SpecLoadError.self) { try SpecLoader.load(data: Self.validJSON(background: ##"{ "colorHex": "white" }"##)) }
        #expect(throws: SpecLoadError.self) { try SpecLoader.load(data: Self.validJSON(background: ##"{ "colorHex": "#FFF" }"##)) }
    }

    @Test("sources must not be empty")
    func emptySources() {
        #expect(throws: SpecLoadError.self) { try SpecLoader.load(data: Self.validJSON(sources: "[]")) }
    }

    @Test("every problem is reported at once, not just the first")
    func reportsAllIssues() {
        do {
            _ = try SpecLoader.load(data: Self.validJSON(id: "Bad Id", countryCode: "zz", sources: "[]"))
            Issue.record("expected validation to fail")
        } catch let SpecLoadError.invalid(error) {
            #expect(error.issues.count >= 3)
        } catch {
            Issue.record("expected .invalid, got \(error)")
        }
    }

    @Test("a missing file reports the path")
    func missingFile() {
        let url = URL(fileURLWithPath: "/nonexistent/spec.json")
        #expect(throws: SpecLoadError.self) { try SpecLoader.load(contentsOf: url) }
    }
}
