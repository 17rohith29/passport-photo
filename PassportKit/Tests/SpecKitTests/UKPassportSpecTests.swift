import Foundation
import Testing
import TestSupport
@testable import SpecKit

@Suite("UK passport spec")
struct UKPassportSpecTests {

    static func spec() throws -> DocumentSpec {
        try SpecLoader.load(contentsOf: #require(RepoPaths.specs)
            .appendingPathComponent("gb-passport.json"))
    }

    @Test("decodes with the values GOV.UK states")
    func decodes() throws {
        let spec = try Self.spec()
        #expect(spec.id == "gb-passport")
        #expect(spec.country.code == "GB")
        #expect(spec.photo.sizeMM == Size(width: 35, height: 45))

        // "from the crown of your head to your chin - must be between 29mm and 34mm high"
        let band = try #require(spec.geometry.headHeight.passMM)
        #expect(band.min == 29.0)
        #expect(band.max == 34.0)
        #expect(spec.geometry.headHeight.targetMM == 31.5)

        // "at least 50KB and no more than 10MB"
        #expect(spec.photo.digital.fileSizeKB == Range(min: 50, max: 10240))
        // "plain cream or light grey background" — not white.
        #expect(spec.background?.colorHex != "#FFFFFF")
        #expect(spec.sources.allSatisfy { $0.authority == .official })
    }

    /// GOV.UK's own two pages disagree on shape: 600x750 is 4:5, 35x45 mm is 7:9. Taking the
    /// digital minimum literally would stretch every face about 2.9% wider.
    @Test("the output keeps the printed aspect ratio while clearing the digital minimum")
    func aspectRatioIsNotStretched() throws {
        let spec = try Self.spec()
        let px = try #require(spec.photo.digital.sizePx)
        let mm = spec.photo.sizeMM

        #expect(abs(px.width / px.height - mm.width / mm.height) < 1e-9,
                "px \(px.width)x\(px.height) does not match \(mm.width)x\(mm.height) mm")
        // Still satisfies "at least 600 pixels wide and 750 pixels tall".
        #expect(px.width >= 600)
        #expect(px.height >= 750)
        // And the naive reading really would have stretched it.
        #expect(abs(600.0 / 750.0 - mm.width / mm.height) > 0.02)
    }

    @Test("geometry derives from the pixel size")
    func geometry() throws {
        let spec = try Self.spec()
        let geometry = try #require(SpecGeometry(spec: spec))
        #expect(abs(geometry.pxPerMM - 900.0 / 45.0) < 1e-9)
        #expect(abs(geometry.requiredHeadPx - 31.5 * 20.0) < 1e-6)
    }

    @Test("all four documents differ where they should")
    func fourDocuments() throws {
        let ids = ["in-passport", "us-passport", "eu-schengen-visa", "gb-passport"]
        let specs = try ids.map { id in
            try SpecLoader.load(contentsOf: #require(RepoPaths.specs).appendingPathComponent("\(id).json"))
        }
        #expect(Set(specs.map(\.id)).count == 4)
        // Two white and two grey backgrounds.
        #expect(Set(specs.map { $0.background?.colorHex ?? "" }).count == 2)
        // Four different head-height bands.
        let bands = specs.compactMap { $0.geometry.headHeight.passMM.map { "\($0.min)-\($0.max)" } }
        #expect(Set(bands).count == bands.count)
    }
}
