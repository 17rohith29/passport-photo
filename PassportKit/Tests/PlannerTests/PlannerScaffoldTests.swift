import Foundation
import Testing
import TestSupport
import SpecKit
import PhotoPipeline

/// Pure geometry, no images. Crop planning, eye-line clamping and edge crops land here at M3.
@Suite("Planner scaffold")
struct PlannerScaffoldTests {

    @Test("the pipeline target is linked and pure geometry can run without images")
    func targetsAreWired() {
        #expect(PhotoPipeline.milestone.hasPrefix("M0"))
    }

    @Test("both specs drive geometry from data alone")
    func geometryFromBothSpecs() throws {
        for url in [try #require(RepoPaths.inPassportSpec), try #require(RepoPaths.squareTestSpec)] {
            let spec = try SpecLoader.load(contentsOf: url)
            let geometry = try #require(SpecGeometry(spec: spec))
            #expect(geometry.pxPerMM > 0)
            #expect(geometry.requiredHeadPx > 0)
        }
    }
}
