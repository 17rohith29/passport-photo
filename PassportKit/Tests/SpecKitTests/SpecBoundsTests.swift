import Foundation
import Testing
@testable import SpecKit

/// "Countries are data" only holds if a data file cannot take the app down or make every photo
/// fail. Each case here passed `validate()` before these rules went in.
@Suite("Spec bounds and self-consistency")
struct SpecBoundsTests {

    static func json(sizeMM: String = #"{ "width": 35, "height": 45 }"#,
                     printBlock: String = #"{ "dpi": 300 }"#,
                     digital: String = #"{ "sizePx": { "width": 630, "height": 810 }, "format": "jpeg" }"#,
                     background: String = ##"{ "colorHex": "#FFFFFF" }"##,
                     input: String? = nil,
                     headHeight: String = #"{ "measure": "chinToCrown", "passMM": { "min": 30, "max": 34 } }"#) -> Data {
        Data("""
        {
          "schemaVersion": 1, "id": "zz-bounds",
          "country": { "code": "ZZ", "name": "Testland" },
          "document": { "type": "other", "displayName": "Test" },
          "status": { "lastVerified": "2026-09-25", "confidence": "low" },
          "photo": { "sizeMM": \(sizeMM), "digital": \(digital), "print": \(printBlock) },
          "geometry": { "headHeight": \(headHeight) },
          "background": \(background),
          \(input.map { "\"input\": \($0)," } ?? "")
          "sources": [{ "title": "t", "url": "about:blank", "authority": "third-party" }]
        }
        """.utf8)
    }

    @Test("the baseline used by this suite is valid")
    func baselineLoads() throws {
        _ = try SpecLoader.load(data: Self.json())
    }

    /// 1e30 is finite and positive, and `Int(1e30)` traps. These values are multiplied into
    /// pixel counts, buffer lengths and print-tile sizes.
    @Test("an absurdly large but finite value is rejected, not converted")
    func hugeValuesRejected() {
        #expect(throws: SpecLoadError.self) {
            try SpecLoader.load(data: Self.json(printBlock: #"{ "dpi": 1e30 }"#))
        }
        #expect(throws: SpecLoadError.self) {
            try SpecLoader.load(data: Self.json(
                sizeMM: #"{ "width": 1e30, "height": 1e30 }"#,
                headHeight: #"{ "measure": "chinToCrown", "passFraction": { "min": 0.7, "max": 0.8 } }"#
            ))
        }
        #expect(throws: SpecLoadError.self) {
            try SpecLoader.load(data: Self.json(
                digital: #"{ "sizePx": { "width": 1e12, "height": 1e12 }, "format": "jpeg" }"#
            ))
        }
    }

    @Test("real-world sizes are still accepted")
    func realisticValuesAccepted() throws {
        // Canada is the largest shipping photo, and 1200 dpi is a plausible print setting.
        _ = try SpecLoader.load(data: Self.json(
            sizeMM: #"{ "width": 50, "height": 70 }"#,
            printBlock: #"{ "dpi": 1200 }"#,
            digital: #"{ "sizePx": { "width": 2362, "height": 3307 }, "format": "jpeg" }"#,
            headHeight: #"{ "measure": "chinToCrown", "passMM": { "min": 31, "max": 36 } }"#
        ))
    }

    /// A background darker than its own purity floor fails every correctly rendered photo and
    /// then blames the user for it.
    @Test("a background colour below its own minChannelValue is rejected")
    func selfContradictoryBackgroundRejected() {
        #expect(throws: SpecLoadError.self) {
            try SpecLoader.load(data: Self.json(
                background: ##"{ "colorHex": "#CCCCCC", "minChannelValue": 245 }"##
            ))
        }
    }

    @Test("a background colour at or above its floor still loads")
    func consistentBackgroundAccepted() throws {
        // #F0F0F0 is 240, which is exactly the UK and Schengen pairing.
        _ = try SpecLoader.load(data: Self.json(
            background: ##"{ "colorHex": "#F0F0F0", "minChannelValue": 235 }"##
        ))
        _ = try SpecLoader.load(data: Self.json(
            background: ##"{ "colorHex": "#F0F0F0", "minChannelValue": 240 }"##
        ))
    }

    /// The renderer never upscales, so a spec must not be able to claim it may.
    @Test("a spec cannot permit upscaling")
    func upscalingCannotBePermitted() throws {
        #expect(throws: SpecLoadError.self) {
            try SpecLoader.load(data: Self.json(input: #"{ "allowUpscaling": true }"#))
        }
        _ = try SpecLoader.load(data: Self.json(input: #"{ "allowUpscaling": false }"#))
    }

    /// The digital JPEG's DPI metadata has to describe the file, not the print tiles.
    @Test("digitalDPI describes the file's real density, not print.dpi")
    func digitalDPIIsTheFilesOwnDensity() throws {
        let spec = try SpecLoader.load(data: Self.json())
        let geometry = try #require(SpecGeometry(spec: spec))
        // 810 px over 45 mm is 18 px/mm, which is 457.2 ppi - not the 300 used for print tiles.
        #expect(abs(geometry.digitalDPI - 457.2) < 0.1)
        #expect(geometry.digitalDPI != spec.photo.print.dpi)
    }

    @Test("every shipping document's digitalDPI reproduces its physical size")
    func digitalDPIRoundTripsForEveryDocument() throws {
        for spec in try PrintGuidanceSpecs.all() {
            let geometry = try #require(SpecGeometry(spec: spec), "\(spec.id)")
            let px = try #require(spec.photo.digital.outputSizePx)
            // Printing at the embedded density must give back the spec's millimetres.
            let heightMM = px.height / geometry.digitalDPI * 25.4
            let widthMM = px.width / geometry.digitalDPI * 25.4
            #expect(abs(heightMM - spec.photo.sizeMM.height) < 0.05, "\(spec.id) height")
            #expect(abs(widthMM - spec.photo.sizeMM.width) < 0.6, "\(spec.id) width")
        }
    }
}

/// Loads the shipping specs from disk for suites that need all of them.
enum PrintGuidanceSpecs {
    static func all() throws -> [DocumentSpec] {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("specs")
        return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.contains("schema") }
            .map { try SpecLoader.load(contentsOf: $0) }
            .filter { $0.status.isTestFixture != true }
            .sorted { $0.id < $1.id }
    }
}
