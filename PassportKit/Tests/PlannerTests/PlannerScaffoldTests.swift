import CoreGraphics
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

/// Specs state the same rule in different units. Anything that reads only one form silently
/// drops that rule for some country, it hid the head height for the EU and the eye line for the
/// US in the requirements sheet, and skipped the head check entirely in ComplianceChecker.
@Suite("Every spec is renderable")
struct SpecRenderabilityTests {

    static func allSpecs() throws -> [DocumentSpec] {
        let root = try #require(RepoPaths.specs)
        let urls = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? [])
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != "document-spec.schema.json" }
        return try urls.map { try SpecLoader.load(contentsOf: $0) }
    }

    @Test("every spec resolves a head-height band in millimetres")
    func headBandAlwaysResolves() throws {
        let specs = try Self.allSpecs()
        #expect(specs.count >= 3)
        for spec in specs {
            let band = HeadHeightBand.inMM(spec: spec)
            #expect(band != nil, "\(spec.id) has no resolvable head band")
            if let band {
                #expect(band.max > band.min, "\(spec.id) band \(band)")
                #expect(band.min > 0, "\(spec.id) band \(band)")
                #expect(band.max <= spec.photo.sizeMM.height, "\(spec.id) head taller than the photo")
            }
        }
    }

    @Test("every spec's eye line resolves to a fraction, when it states one")
    func eyeLineResolves() throws {
        for spec in try Self.allSpecs() {
            guard spec.geometry.eyeLine != nil else { continue }
            let band = CropPlanner.eyeLineBand(spec: spec, photoHeightMM: spec.photo.sizeMM.height)
            #expect(band != nil, "\(spec.id) states an eye line that does not resolve")
            if let band {
                #expect(band.min > 0 && band.max < 1, "\(spec.id) eye band \(band)")
            }
        }
    }

    @Test("every spec derives geometry and a plausible required head size")
    func geometryAlwaysDerives() throws {
        for spec in try Self.allSpecs() {
            let geometry = try #require(SpecGeometry(spec: spec), "\(spec.id) has no geometry")
            #expect(geometry.pxPerMM > 0, "\(spec.id)")
            #expect(geometry.requiredHeadPx > 0, "\(spec.id)")
            // The required head must fit inside the output it is measured against.
            #expect(geometry.requiredHeadPx < geometry.outputSizePx.height, "\(spec.id)")
        }
    }

    @Test("every real spec names a background colour the renderer can parse")
    func backgroundParses() throws {
        for spec in try Self.allSpecs() {
            let hex = try #require(spec.background?.colorHex, "\(spec.id) has no background")
            #expect(RGB(hex: hex) != nil, "\(spec.id) background \(hex) does not parse")
        }
    }

    @Test("a spec that states its head band only as a fraction still plans a crop")
    func fractionOnlySpecPlans() throws {
        let schengen = try #require(try Self.allSpecs().first { $0.id == "eu-schengen-visa" })
        #expect(schengen.geometry.headHeight.passMM == nil)

        // A head 1800 px tall in a 4284x5712 source, eyes level and centred.
        let plan = CropPlanner.plan(
            crown: 900, chin: 2700,
            eyes: (CGPoint(x: 2000, y: 1700), CGPoint(x: 2400, y: 1700)),
            imageSize: CGSize(width: 4284, height: 5712), spec: schengen
        )
        switch plan {
        case let .success(value):
            #expect(value.rect.height > 0)
            // 35:45 aspect, from the spec and nothing else.
            #expect(abs(value.rect.width / value.rect.height - 35.0 / 45.0) < 1e-6)
        case let .failure(error):
            Issue.record("fraction-only spec failed to plan: \(error)")
        }
    }
}
