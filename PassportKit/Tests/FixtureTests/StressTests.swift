import CoreGraphics
import Foundation
import Testing
import TestSupport
import PhotoAnalysis
import PhotoPipeline
import SpecKit

/// The binary must not die. This runs a large third-party portrait set against every supported
/// document — hundreds of runs across eight different geometries — and asserts only that the
/// pipeline always returns, always explains itself, and never emits an out-of-spec photo.
///
/// Third-party photos are gitignored, so this skips on a clean clone.
@Suite("Stress", .serialized, .enabled(if: RepoPaths.hasCalibrationPhotos))
struct StressTests {

    static func specs() throws -> [DocumentSpec] {
        let root = try #require(RepoPaths.specs)
        let urls = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? [])
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != "document-spec.schema.json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try urls.map { try SpecLoader.load(contentsOf: $0) }
            .filter { $0.status.isTestFixture != true }
    }

    static func photos(limit: Int) throws -> [URL] {
        let dir = try #require(RepoPaths.calibrationPhotos)
        return (try FileManager.default.contentsOfDirectory(atPath: dir.path))
            .filter { $0.lowercased().hasSuffix(".jpg") }
            .sorted()
            .prefix(limit)
            .map { dir.appendingPathComponent($0) }
    }

    /// Every photo against every document. The contract is narrow and absolute.
    @Test("hundreds of runs across eight documents, and the binary survives")
    func everyPhotoEveryDocument() async throws {
        let specs = try Self.specs()
        let photos = try Self.photos(limit: 240)
        #expect(specs.count == 8)
        #expect(photos.count >= 40, "only \(photos.count) photos")

        var runs = 0
        var rendered = 0
        var problems: [String] = []
        var perSpec: [String: Int] = [:]

        for url in photos {
            guard let image = try? ImageLoader.load(
                contentsOf: url, maxPixelSize: ImageLoader.defaultMaxPixelSize
            ) else { continue }

            for spec in specs {
                let result = await PassportPipeline().run(image, spec: spec)
                runs += 1
                let name = url.lastPathComponent

                // 1. Always returns something explicable.
                if result.output == nil, result.failures.isEmpty, result.failureReason == nil {
                    problems.append("\(name)/\(spec.id): refused with no reason at all")
                }
                // 2. Every failure carries a measurement and a requirement.
                for failure in result.failures where failure.measured.isEmpty || failure.requirement.isEmpty {
                    problems.append("\(name)/\(spec.id): \(failure.id.rawValue) has no detail")
                }

                guard let output = result.output else { continue }
                rendered += 1
                perSpec[spec.id, default: 0] += 1

                // 3. Anything rendered is the exact size the spec demands.
                guard let geometry = SpecGeometry(spec: spec) else { continue }
                let expected = geometry.outputSizePx
                if output.digital.width != Int(expected.width)
                    || output.digital.height != Int(expected.height) {
                    problems.append("\(name)/\(spec.id): wrong size \(output.digital.width)x\(output.digital.height)")
                }
                // 4. Anything ACCEPTED is inside its own head band. An accepted photo that is out
                //    of spec is worse than a rejection, because the user trusts it.
                if result.failures.isEmpty, let band = HeadHeightBand.inMM(spec: spec) {
                    let headMM = geometry.pxToMM(
                        Double(output.digital.height) * (output.chinFraction - output.crownFraction)
                    )
                    if headMM < band.min - 0.01 || headMM > band.max + 0.01 {
                        problems.append(String(format: "%@/%@: ACCEPTED at head %.2f mm, outside %.1f-%.1f",
                                               name, spec.id, headMM, band.min, band.max))
                    }
                }
                // 5. And inside its file-size range.
                if result.failures.isEmpty, let kb = spec.photo.digital.fileSizeKB,
                   output.digitalSizeKB < kb.min || output.digitalSizeKB > kb.max {
                    problems.append(String(format: "%@/%@: ACCEPTED at %.0f KB, outside %.0f-%.0f",
                                           name, spec.id, output.digitalSizeKB, kb.min, kb.max))
                }
            }
        }

        var lines = ["\(runs) runs over \(photos.count) photos x \(specs.count) documents; rendered \(rendered)"]
        for (id, count) in perSpec.sorted(by: { $0.key < $1.key }) {
            lines.append("  \(id): \(count) rendered")
        }
        print("STRESS\n" + lines.joined(separator: "\n"))

        let summary = problems.prefix(25).joined(separator: "\n")
        #expect(problems.isEmpty, "\(problems.count) problems:\n\(summary)")
    }

    /// Adversarial synthetic input against every document, since a country file changes every
    /// buffer size and divisor in the pipeline.
    @Test("junk input cannot crash any document")
    func junkAgainstEveryDocument() async throws {
        let images: [CGImage] = [
            BadInputTests.solid(width: 1, height: 1, grey: 128),
            BadInputTests.solid(width: 3000, height: 4, grey: 200),
            BadInputTests.solid(width: 4, height: 3000, grey: 200),
            BadInputTests.solid(width: 64, height: 64, grey: 255),
            BadInputTests.noise(width: 800, height: 1000),
            BadInputTests.noise(width: 200, height: 200, seed: 7),
        ]
        for spec in try Self.specs() {
            for image in images {
                let result = await PassportPipeline().run(image, spec: spec)
                // Junk must never produce a photo, and must always say something.
                #expect(result.output == nil, "\(spec.id) rendered junk")
                #expect(!result.failures.isEmpty || result.failureReason != nil,
                        "\(spec.id) refused junk silently")
            }
        }
    }
}
