import CoreGraphics
import Foundation
import Testing
import TestSupport
import PhotoAnalysis
import PhotoPipeline
import SpecKit

/// Nothing in the pipeline knows what a country is. This runs the golden photo through every
/// supported document and checks each output against that document's own numbers.
@Suite("All documents pipeline", .serialized, .enabled(if: RepoPaths.hasFixturePhotos))
struct AllDocumentsPipelineTests {

    static func specs() throws -> [DocumentSpec] {
        let root = try #require(RepoPaths.specs)
        let urls = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? [])
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != "document-spec.schema.json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try urls.map { try SpecLoader.load(contentsOf: $0) }
            .filter { $0.status.isTestFixture != true }
    }

    static func golden() throws -> CGImage {
        try ImageLoader.load(contentsOf: #require(RepoPaths.fixtures)
            .appendingPathComponent("photos/IMG_0012.HEIC"))
    }

    @Test("the golden photo produces a compliant photo for every document")
    func everyDocumentSucceeds() async throws {
        let image = try Self.golden()
        var report: [String] = []
        var problems: [String] = []

        for spec in try Self.specs() {
            let result = await PassportPipeline().run(image, spec: spec)
            guard let output = result.output else {
                problems.append("\(spec.id): no output — \(result.failureReason ?? "?")")
                continue
            }
            let geometry = try #require(SpecGeometry(spec: spec))
            let headMM = geometry.pxToMM(
                Double(output.digital.height) * (output.chinFraction - output.crownFraction)
            )
            let band = try #require(HeadHeightBand.inMM(spec: spec))

            PipelineFixtureTests.write(output.digital, named: "all_\(spec.id).png")
            report.append(String(
                format: "%-18@ %4dx%-4d head %.2f mm (need %.1f-%.1f)  %.0f KB  %@",
                spec.id as NSString, output.digital.width, output.digital.height,
                headMM, band.min, band.max, output.digitalSizeKB,
                "\(result.verdict)" as NSString
            ))

            if headMM < band.min || headMM > band.max {
                problems.append(String(format: "%@: head %.2f mm outside %.1f-%.1f",
                                       spec.id, headMM, band.min, band.max))
            }
            // The output must be the exact pixel size the spec asks for.
            let expected = geometry.outputSizePx
            if output.digital.width != Int(expected.width) || output.digital.height != Int(expected.height) {
                problems.append("\(spec.id): output \(output.digital.width)x\(output.digital.height) != spec \(Int(expected.width))x\(Int(expected.height))")
            }
            // And inside its own file-size range, when it states one.
            if let kb = spec.photo.digital.fileSizeKB,
               output.digitalSizeKB < kb.min || output.digitalSizeKB > kb.max {
                problems.append(String(format: "%@: %.0f KB outside %.0f-%.0f",
                                       spec.id, output.digitalSizeKB, kb.min, kb.max))
            }
            for failure in result.failures {
                problems.append("\(spec.id): failed \(failure.id.rawValue) — \(failure.measured)")
            }
        }

        print("ALL DOCUMENTS\n" + report.joined(separator: "\n"))
        let summary = problems.joined(separator: "\n")
        #expect(problems.isEmpty, "\(summary)")
    }

    @Test("a rejected photo is rejected by every document")
    func rejectionsAreUniversal() async throws {
        // IMG_0010 is side-lit; lighting is the one thing no document tolerates.
        let image = try ImageLoader.load(contentsOf: #require(RepoPaths.fixtures)
            .appendingPathComponent("photos/IMG_0010.HEIC"))
        var accepted: [String] = []
        for spec in try Self.specs() {
            let result = await PassportPipeline().run(image, spec: spec)
            if result.output != nil, result.failures.isEmpty { accepted.append(spec.id) }
        }
        #expect(accepted.isEmpty, "side-lit photo accepted by \(accepted)")
    }

    /// China allows 20 degrees of turn where everyone else allows 8, so the same photo can pass
    /// one document and fail another. That is the specs doing their job, not a bug.
    @Test("documents disagree where their rules disagree")
    func documentsDisagree() async throws {
        let specs = try Self.specs()
        let china = try #require(specs.first { $0.id == "cn-visa" })
        let india = try #require(specs.first { $0.id == "in-passport" })
        #expect(china.pose?.yawDeg?.failAbove == 20)
        #expect(india.pose?.yawDeg?.failAbove == 8)
        // Canada frames far looser than India.
        let canada = try #require(specs.first { $0.id == "ca-passport" })
        let canadaFraction = 33.5 / canada.photo.sizeMM.height
        let indiaFraction = 36.0 / india.photo.sizeMM.height
        #expect(canadaFraction < indiaFraction * 0.7, "ca \(canadaFraction) in \(indiaFraction)")
    }
}
