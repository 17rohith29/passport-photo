import Foundation
import Testing
import TestSupport
@testable import SpecKit

/// The US spec is the proof that a second country is data, not code.
@Suite("US passport spec")
struct USPassportSpecTests {

    static func spec() throws -> DocumentSpec {
        try SpecLoader.load(contentsOf: #require(RepoPaths.usPassportSpec))
    }

    @Test("decodes with the values 8 FAM 402.1 states")
    func decodes() throws {
        let spec = try Self.spec()
        #expect(spec.id == "us-passport")
        #expect(spec.country.code == "US")
        #expect(spec.document.type == .passport)
        #expect(spec.status.confidence == .high)
        #expect(spec.status.isTestFixture == nil)

        // 2 x 2 inches.
        #expect(spec.photo.sizeMM == Size(width: 50.8, height: 50.8))
        #expect(abs(spec.photo.sizeMM.width / 25.4 - 2.0) < 1e-9)

        // 1 inch to 1 3/8 inches, chin to top of head.
        let band = try #require(spec.geometry.headHeight.passMM)
        #expect(band.min == 25.0)
        #expect(band.max == 35.0)
        #expect(spec.geometry.headHeight.targetMM == 30.0)

        #expect(spec.photo.digital.fileSizeKB == Range(min: 54, max: 10240))
        #expect(spec.appearance?.glassesAllowed == false)
        // The ears do not have to be visible in a US photo; they do for India.
        #expect(spec.appearance?.earsVisible == false)
    }

    @Test("the official head band brackets 1 and 1 3/8 inches")
    func headBandMatchesInches() throws {
        let band = try #require(try Self.spec().geometry.headHeight.passMM)
        let oneInch = 25.4, oneAndThreeEighths = 1.375 * 25.4
        // The published 25-35 mm is a rounding of the inch figures, so it must contain neither
        // more nor less than a millimetre of slack at each end.
        #expect(abs(band.min - oneInch) < 0.5, "min \(band.min) vs \(oneInch)")
        #expect(abs(band.max - oneAndThreeEighths) < 0.5, "max \(band.max) vs \(oneAndThreeEighths)")
    }

    @Test("the target sits mid-band, because our crown and chin read large")
    func targetIsMidBand() throws {
        let spec = try Self.spec()
        let band = try #require(spec.geometry.headHeight.passMM)
        let target = try #require(spec.geometry.headHeight.targetMM)
        // 8 FAM measures skull-top to chin, excluding hair and beard; this app measures the hair
        // mass and the beard, so it reads larger. Mid-band keeps a conservative measurement inside.
        #expect(abs(target - (band.min + band.max) / 2) < 0.01)
        #expect(target - band.min >= 4.0)
        #expect(band.max - target >= 4.0)
    }

    @Test("geometry is square and derived from the pixel range, not dpi")
    func geometry() throws {
        let spec = try Self.spec()
        let geometry = try #require(SpecGeometry(spec: spec))

        #expect(geometry.outputSizePx == Size(width: 1200, height: 1200))
        #expect(geometry.outputSizePx.width == geometry.outputSizePx.height)
        #expect(abs(geometry.pxPerMM - 1200.0 / 50.8) < 1e-9)
        #expect(abs(geometry.requiredHeadPx - 30.0 * (1200.0 / 50.8)) < 1e-6)
        // Print tiles: 2 inches at 300 dpi.
        #expect(SpecGeometry.printTilePx(spec: spec) == Size(width: 600, height: 600))
    }

    @Test("every source is official and the risky ones are called out")
    func sourcing() throws {
        let spec = try Self.spec()
        #expect(!spec.sources.isEmpty)
        #expect(spec.sources.allSatisfy { $0.authority == .official })
        #expect(spec.sources.contains { $0.url.contains("fam.state.gov") })
        // The two figures the US does not actually publish must be admitted in the notes.
        let notes = (spec.status.notes ?? []).joined(separator: " ")
        #expect(notes.contains("NO eye-line requirement"))
        #expect(notes.contains("facial hair"))
    }

    @Test("the US and India specs differ in every way that matters")
    func differsFromIndia() throws {
        let us = try Self.spec()
        let india = try SpecLoader.load(contentsOf: #require(RepoPaths.inPassportSpec))

        #expect(us.photo.sizeMM != india.photo.sizeMM)
        #expect(us.geometry.headHeight.passMM != india.geometry.headHeight.passMM)
        #expect(us.photo.digital.sizePx == nil)
        #expect(india.photo.digital.sizePx != nil)
        // India states the eye line as a fraction, the US in millimetres.
        #expect(india.geometry.eyeLine?.fromBottomFraction != nil)
        #expect(us.geometry.eyeLine?.fromBottomMM != nil)
        #expect(us.geometry.eyeLine?.fromBottomFraction == nil)
    }
}
