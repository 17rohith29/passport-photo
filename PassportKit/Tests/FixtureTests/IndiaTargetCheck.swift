import Foundation
import SpecKit
import Testing
import TestSupport
@testable import PhotoAnalysis
@testable import PhotoPipeline

/// India's head band was 35.25-36.75 mm, leaving 0.75 mm of tolerance around a 36 mm target,
/// against a crown/chin measurement LESSONS 1-2 records as reading large. It is now ICAO's
/// 32-36 with a 34 mm target, which is both the only sourced figure and over twice the margin.
/// This pins the margin, because a future narrowing would quietly reintroduce the old fragility.
@Suite("Head band margin", .serialized, .enabled(if: RepoPaths.hasFixturePhotos))
struct HeadBandMarginTests {

    @Test("an accepted photo lands on target with room on both sides of the band")
    func headLandsOnTargetWithMargin() async throws {
        let spec = try SpecLoader.load(contentsOf: #require(RepoPaths.inPassportSpec))
        let geometry = try #require(SpecGeometry(spec: spec))
        let band = try #require(HeadHeightBand.inMM(spec: spec))
        let target = try #require(spec.geometry.headHeight.targetMM)

        // At least 1.5 mm of room either side of where we aim.
        #expect(target - band.min >= 1.5, "only \(target - band.min) mm below target")
        #expect(band.max - target >= 1.5, "only \(band.max - target) mm above target")

        let url = try #require(RepoPaths.fixtures).appendingPathComponent("photos/IMG_0012.HEIC")
        let image = try ImageLoader.load(data: try Data(contentsOf: url))
        let result = await PassportPipeline().run(image, spec: spec)
        let out = try #require(result.output, "the golden photo stopped producing an output")

        let headPx = Double(out.digital.height) * (out.chinFraction - out.crownFraction)
        let headMM = geometry.pxToMM(headPx)
        #expect(abs(headMM - target) < 0.6, "head landed at \(headMM) mm, aiming for \(target)")
        #expect(headMM > band.min + 1, "head at \(headMM) mm sits on the bottom of \(band)")
        #expect(headMM < band.max - 1, "head at \(headMM) mm sits on the top of \(band)")
    }
}
