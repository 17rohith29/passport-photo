import CoreGraphics
import Foundation
import Testing
import TestSupport
import PhotoAnalysis
import PhotoPipeline
import SpecKit

@Suite("Schengen spec")
struct SchengenSpecTests {

    static func spec() throws -> DocumentSpec {
        try SpecLoader.load(contentsOf: #require(RepoPaths.specs)
            .appendingPathComponent("eu-schengen-visa.json"))
    }

    @Test("decodes, and states the head as a fraction like the Commission does")
    func decodes() throws {
        let spec = try Self.spec()
        #expect(spec.id == "eu-schengen-visa")
        #expect(spec.country.code == "EU")
        #expect(spec.document.type == .visa)
        #expect(spec.photo.sizeMM == Size(width: 35, height: 45))

        // The Commission publishes a percentage, not millimetres.
        #expect(spec.geometry.headHeight.passMM == nil)
        #expect(spec.geometry.headHeight.passFraction == Range(min: 0.70, max: 0.80))

        // Glasses are allowed here and nowhere else so far.
        #expect(spec.appearance?.glassesAllowed == true)
        // And the background is not white.
        #expect(spec.background?.colorHex == "#F0F0F0")
    }

    @Test("a fraction-stated head band resolves to millimetres")
    func bandResolves() throws {
        let spec = try Self.spec()
        let band = try #require(HeadHeightBand.inMM(spec: spec))
        // 70-80% of 45 mm.
        #expect(abs(band.min - 31.5) < 1e-9)
        #expect(abs(band.max - 36.0) < 1e-9)
    }

    /// The bug this spec exposed: reading `passMM` alone left the head unchecked for any spec
    /// that states a fraction, which is the single rule the Commission actually publishes.
    @Test("a fraction-only head band is still enforced, not silently skipped")
    func fractionBandIsEnforced() throws {
        let spec = try Self.spec()
        let geometry = try #require(SpecGeometry(spec: spec))
        let checker = ComplianceChecker()

        // 33.75 mm at this spec's px/mm: inside 31.5-36.0, must pass.
        let good = geometry.mmToPx(33.75)
        // 20 mm: far outside, must fail. Before the fix this returned .pass.
        let bad = geometry.mmToPx(20.0)

        let passing = checker.headHeightCheck(crown: 0, chin: CGFloat(good), geometry: geometry, spec: spec)
        let failing = checker.headHeightCheck(crown: 0, chin: CGFloat(bad), geometry: geometry, spec: spec)

        #expect(passing.status == .pass, "\(passing.measured) vs \(passing.requirement)")
        #expect(failing.status == .fail, "20 mm head was not caught: \(failing.requirement)")
        #expect(failing.requirement.contains("31.5"))
    }

    @Test("all four specs coexist and differ")
    func fourSpecs() throws {
        let urls = [RepoPaths.inPassportSpec, RepoPaths.usPassportSpec,
                    RepoPaths.specs?.appendingPathComponent("eu-schengen-visa.json")]
        let specs = try urls.map { try SpecLoader.load(contentsOf: #require($0)) }
        #expect(Set(specs.map(\.id)).count == 3)
        #expect(Set(specs.map { $0.background?.colorHex ?? "" }).count == 2)
        #expect(Set(specs.map { $0.appearance?.glassesAllowed ?? true }).count == 2)
    }
}

@Suite("Schengen pipeline", .serialized, .enabled(if: RepoPaths.hasFixturePhotos))
struct SchengenPipelineTests {

    @Test("IMG_0012 produces a compliant Schengen photo on a grey background")
    func goldenCase() async throws {
        let spec = try SchengenSpecTests.spec()
        let image = try ImageLoader.load(contentsOf: #require(RepoPaths.fixtures)
            .appendingPathComponent("photos/IMG_0012.HEIC"))
        let result = await PassportPipeline().run(image, spec: spec)

        let lines = result.allChecks.map {
            "    \($0.status.rawValue.uppercased())  \($0.id.rawValue): \($0.measured)  [need \($0.requirement)]"
        }
        print("SCHENGEN IMG_0012 verdict \(result.verdict)\n" + lines.joined(separator: "\n"))

        let output = try #require(result.output, "no output: \(result.failureReason ?? "-")")
        PipelineFixtureTests.write(output.digital, named: "IMG_0012_schengen.png")

        let geometry = try #require(SpecGeometry(spec: spec))
        let headMM = geometry.pxToMM(Double(output.digital.height)
            * (output.chinFraction - output.crownFraction))
        // 70-80% of 45 mm.
        #expect(headMM >= 31.5 && headMM <= 36.0, "head \(headMM) mm")
        #expect(result.failures.isEmpty, "\(result.failures.map(\.id.rawValue))")

        // The background really is the grey the spec asked for, not white.
        let pixels = try #require(ImageConversion.pixelImage(from: output.digital))
        let corner = pixels.offset(x: 2, y: 2)
        #expect(pixels.pixels[corner] == 240, "corner red \(pixels.pixels[corner])")
        #expect(pixels.pixels[corner + 1] == 240)
        #expect(pixels.pixels[corner + 2] == 240)
    }

    @Test("bad photos are rejected under Schengen too")
    func badPhotosRejected() async throws {
        let spec = try SchengenSpecTests.spec()
        let suite = try FixtureManifestTests.loadSuite()
        let fixtures = try #require(RepoPaths.fixtures)
        var wronglyAccepted: [String] = []

        for testCase in suite.cases where testCase.expect == .reject {
            let url = fixtures.appendingPathComponent(testCase.file)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let result = await PassportPipeline().run(try ImageLoader.load(contentsOf: url), spec: spec)
            if result.output != nil { wronglyAccepted.append(testCase.fileName) }
        }
        #expect(wronglyAccepted.isEmpty, "accepted under Schengen: \(wronglyAccepted)")
    }
}
