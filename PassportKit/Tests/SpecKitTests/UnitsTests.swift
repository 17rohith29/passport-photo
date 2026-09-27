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

    @Test("required head px is derived the same way as the Python reference")
    func requiredHeadPxMatchesOracle() throws {
        let spec = try SpecLoader.load(contentsOf: #require(RepoPaths.inPassportSpec))
        let geometry = try #require(SpecGeometry(spec: spec))
        let px = try #require(spec.photo.digital.outputSizePx)

        // reference/python/auto_passport.py: need = px[1] * head_mm_target / size_mm[1].
        // What is being cross-validated is the DERIVATION, not a constant. India's target was
        // 36 mm when the reference was written, giving 648; it is now 34 mm because India's own
        // booklet states no head figure and ICAO, the only source in the file that does, says
        // 32-36 mm. Pinning 648 would pin the old spec value, not the formula.
        let head = try #require(spec.geometry.headHeight.targetMM)
        let reference = px.height * head / spec.photo.sizeMM.height
        #expect(abs(geometry.requiredHeadPx - reference) < 1e-9)

        // The formula, fed the reference's own 36 mm, still reproduces its 648 exactly.
        #expect(abs(px.height * 36.0 / spec.photo.sizeMM.height - 648.0) < 1e-9)
    }

    @Test("IMG_0012's ground-truth head height clears the requirement, the far shots do not")
    func oracleHeadRatios() throws {
        let spec = try SpecLoader.load(contentsOf: #require(RepoPaths.inPassportSpec))
        let geometry = try #require(SpecGeometry(spec: spec))
        // fixtures/expected.json groundTruth for IMG_0012: headHeightPx 1800.
        #expect(1800.0 / geometry.requiredHeadPx > 2.7)

        // Three-way cross-check: the px-per-mm derivation, the oracle's
        // head_px_ratio_vs_required (2.82) and the hand-placed ground truth (1800 px) are
        // independently derived, so ratio * required must land near 1800. It comes out at
        // 1827, 1.5% high, because the Python ratio uses its est_head = (chin - brow) * 1.64
        // estimate rather than a measured crown.
        //
        // The ratio is defined against the ORACLE's required, which came from its own 36 mm
        // target. Multiplying it by our required conflated the two, and only looked right
        // while both targets happened to be 36. India's is now 34, so the oracle's figure is
        // reconstructed from its own head_mm here.
        let px = try #require(spec.photo.digital.outputSizePx)
        let oracleRequired = px.height * 36.0 / spec.photo.sizeMM.height
        let oracleHeadPx = 2.82 * oracleRequired
        #expect(abs(oracleHeadPx - 1800) / 1800 < 0.03)
        // The same arithmetic with dpi-derived px/mm would give 425 px and blow this apart.
        #expect(abs(2.82 * 36.0 * Units.mmToPx(1, dpi: 300) - 1800) / 1800 > 0.3)
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
