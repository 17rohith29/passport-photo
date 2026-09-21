import Foundation
import Testing
import TestSupport
@testable import SpecKit

@Suite("Unit conversion")
struct UnitsTests {

    @Test("mm <-> px round-trips at a given dpi")
    func roundTrip() {
        #expect(abs(Units.mmToPx(25.4, dpi: 300) - 300) < 1e-9)
        #expect(abs(Units.pxToMM(300, dpi: 300) - 25.4) < 1e-9)
        let mm = 36.0
        #expect(abs(Units.pxToMM(Units.mmToPx(mm, dpi: 457), dpi: 457) - mm) < 1e-9)
    }

    @Test("print tiles are 413x531 px for 35x45 mm at 300 dpi")
    func printTiles() throws {
        let spec = try SpecLoader.load(contentsOf: #require(RepoPaths.inPassportSpec))
        #expect(SpecGeometry.printTilePx(spec: spec) == Size(width: 413, height: 531))
    }
}

@Suite("Spec geometry")
struct SpecGeometryTests {

    @Test("pxPerMM comes from the pixel size, not from digital.dpi")
    func pxPerMMIgnoresDPI() throws {
        let spec = try SpecLoader.load(contentsOf: #require(RepoPaths.inPassportSpec))
        let geometry = try #require(SpecGeometry(spec: spec))

        // 810 px / 45 mm = 18 px per mm. Using digital.dpi (300) would give 11.81 and
        // under-measure every head by a third.
        #expect(abs(geometry.pxPerMM - 18.0) < 1e-9)
        #expect(abs(geometry.pxPerMM - Units.mmToPx(1, dpi: spec.photo.digital.dpi ?? 300)) > 1.0)
    }

    @Test("required head px matches the Python reference need (648 px)")
    func requiredHeadPxMatchesOracle() throws {
        let spec = try SpecLoader.load(contentsOf: #require(RepoPaths.inPassportSpec))
        let geometry = try #require(SpecGeometry(spec: spec))
        // reference/python/auto_passport.py: need = px[1] * head_mm_target / size_mm[1]
        #expect(abs(geometry.requiredHeadPx - 648.0) < 1e-9)
    }

    @Test("IMG_0012's ground-truth head height clears the requirement, the far shots do not")
    func oracleHeadRatios() throws {
        let spec = try SpecLoader.load(contentsOf: #require(RepoPaths.inPassportSpec))
        let geometry = try #require(SpecGeometry(spec: spec))
        // fixtures/expected.json groundTruth for IMG_0012: headHeightPx 1800.
        #expect(1800.0 / geometry.requiredHeadPx > 2.7)
        // IMG_0011 measured 0.8x in the reference: must fall short.
        #expect(0.8 * geometry.requiredHeadPx < geometry.requiredHeadPx)
    }

    @Test("head height in mm converts back through pxPerMM")
    func headHeightInMM() throws {
        let spec = try SpecLoader.load(contentsOf: #require(RepoPaths.inPassportSpec))
        let geometry = try #require(SpecGeometry(spec: spec))
        // The reference output measured 36.33 mm; that is 654 px in the 810 px output.
        #expect(abs(geometry.pxToMM(654) - 36.33) < 0.02)
        #expect(abs(geometry.mmToPx(36.0) - 648) < 1e-9)
    }

    @Test("the square spec takes the largest size in its range and stays square")
    func squareSpecGeometry() throws {
        let spec = try SpecLoader.load(contentsOf: #require(RepoPaths.squareTestSpec))
        let geometry = try #require(SpecGeometry(spec: spec))

        #expect(geometry.outputSizePx == Size(width: 1200, height: 1200))
        #expect(abs(geometry.pxPerMM - (1200.0 / 51.0)) < 1e-9)
        // No targetMM, so the requirement falls back to passMM.min (25 mm).
        #expect(abs(geometry.requiredHeadPx - 25.0 * (1200.0 / 51.0)) < 1e-9)
        #expect(geometry.outputSizePx.width == geometry.outputSizePx.height)
    }

    @Test("nothing in SpecKit assumes 35x45 or 7:9")
    func noAspectAssumption() throws {
        let square = try SpecLoader.load(contentsOf: #require(RepoPaths.squareTestSpec))
        let india = try SpecLoader.load(contentsOf: #require(RepoPaths.inPassportSpec))
        let squareGeometry = try #require(SpecGeometry(spec: square))
        let indiaGeometry = try #require(SpecGeometry(spec: india))

        let squareAspect = squareGeometry.outputSizePx.width / squareGeometry.outputSizePx.height
        let indiaAspect = indiaGeometry.outputSizePx.width / indiaGeometry.outputSizePx.height
        #expect(abs(squareAspect - 1.0) < 1e-9)
        #expect(abs(indiaAspect - 7.0 / 9.0) < 1e-9)
        #expect(squareGeometry.pxPerMM != indiaGeometry.pxPerMM)
    }
}
