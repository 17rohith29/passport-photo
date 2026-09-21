import CoreGraphics
import Foundation
import Testing
import TestSupport
import PhotoAnalysis
import PhotoPipeline
import SpecKit

/// Runs the same photos through the US spec. Nothing in the pipeline knows what a country is, so
/// this is the check that the claim holds.
@Suite("US pipeline", .serialized, .enabled(if: RepoPaths.hasFixturePhotos))
struct USPipelineTests {

    static func spec() throws -> DocumentSpec {
        try SpecLoader.load(contentsOf: #require(RepoPaths.usPassportSpec))
    }

    static func image(_ name: String) throws -> CGImage {
        try ImageLoader.load(contentsOf: #require(RepoPaths.fixtures)
            .appendingPathComponent("photos/\(name)"))
    }

    @Test("IMG_0012 produces a compliant US passport photo")
    func goldenCase() async throws {
        let spec = try Self.spec()
        let result = await PassportPipeline().run(try Self.image("IMG_0012.HEIC"), spec: spec)

        let lines = result.allChecks.map {
            "    \($0.status.rawValue.uppercased())  \($0.id.rawValue): \($0.measured)  [need \($0.requirement)]"
        }
        print("US IMG_0012 verdict \(result.verdict)\n" + lines.joined(separator: "\n"))

        let output = try #require(result.output, "no output: \(result.failureReason ?? "-")")
        PipelineFixtureTests.write(output.digital, named: "IMG_0012_us.png")

        // Square, and inside the published pixel range.
        #expect(output.digital.width == output.digital.height)
        #expect(output.digital.width == 1200)

        // The head must land inside 8 FAM's 25-35 mm.
        let geometry = try #require(SpecGeometry(spec: spec))
        let headMM = geometry.pxToMM(Double(output.digital.height)
            * (output.chinFraction - output.crownFraction))
        #expect(headMM >= 25.0 && headMM <= 35.0, "head \(headMM) mm")

        #expect(output.digitalSizeKB >= 54 && output.digitalSizeKB <= 10240)
        #expect(result.verdict != .cannotUse)
        #expect(result.failures.isEmpty, "\(result.failures.map(\.id.rawValue))")
    }

    @Test("the US output is squarer and its head smaller than the India output")
    func differsFromIndiaOutput() async throws {
        let us = await PassportPipeline().run(try Self.image("IMG_0012.HEIC"), spec: try Self.spec())
        let india = await PassportPipeline().run(
            try Self.image("IMG_0012.HEIC"),
            spec: try SpecLoader.load(contentsOf: #require(RepoPaths.inPassportSpec))
        )
        let usOutput = try #require(us.output)
        let indiaOutput = try #require(india.output)

        #expect(usOutput.digital.width == usOutput.digital.height)
        #expect(indiaOutput.digital.width != indiaOutput.digital.height)
        // 30 mm of 50.8 is a smaller share of the frame than 36 mm of 45.
        let usShare = usOutput.chinFraction - usOutput.crownFraction
        let indiaShare = indiaOutput.chinFraction - indiaOutput.crownFraction
        #expect(usShare < indiaShare, "us \(usShare) india \(indiaShare)")
    }

    @Test("bad photos are rejected under the US spec too")
    func badPhotosRejected() async throws {
        let spec = try Self.spec()
        let suite = try FixtureManifestTests.loadSuite()
        let fixtures = try #require(RepoPaths.fixtures)
        var report: [String] = []
        var wronglyAccepted: [String] = []

        for testCase in suite.cases where testCase.expect == .reject {
            let url = fixtures.appendingPathComponent(testCase.file)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let result = await PassportPipeline().run(try ImageLoader.load(contentsOf: url), spec: spec)
            let failed = Set(result.failures.map(\.id.rawValue)).sorted()
            report.append("\(testCase.fileName): \(result.output == nil ? "rejected" : "ACCEPTED") \(failed)")
            if result.output != nil { wronglyAccepted.append(testCase.fileName) }
        }

        print("US REJECTIONS\n" + report.joined(separator: "\n"))
        #expect(wronglyAccepted.isEmpty, "accepted under US: \(wronglyAccepted)")
    }
}
