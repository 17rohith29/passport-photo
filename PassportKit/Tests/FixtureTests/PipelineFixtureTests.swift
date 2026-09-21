import CoreGraphics
import Foundation
import ImageIO
import Testing
import TestSupport
import PhotoAnalysis
import PhotoPipeline
import SpecKit
import UniformTypeIdentifiers

/// The end-to-end suite. CLAUDE.md: look at the outputs, not just the numbers — these write
/// debug images to /tmp/passportkit-debug/ for inspection by eye.
@Suite("Pipeline on fixtures", .enabled(if: RepoPaths.hasFixturePhotos))
struct PipelineFixtureTests {

    static let debugDirectory = URL(fileURLWithPath: "/tmp/passportkit-debug", isDirectory: true)

    static func spec() throws -> DocumentSpec {
        try SpecLoader.load(contentsOf: #require(RepoPaths.inPassportSpec))
    }

    static func image(_ name: String) throws -> CGImage {
        let url = try #require(RepoPaths.fixtures).appendingPathComponent("photos/\(name)")
        return try ImageLoader.load(contentsOf: url)
    }

    static func write(_ image: CGImage, named name: String) {
        try? FileManager.default.createDirectory(at: debugDirectory, withIntermediateDirectories: true)
        let url = debugDirectory.appendingPathComponent(name)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    static func describe(_ checks: [CheckResult]) -> String {
        checks.map { "    \($0.status.rawValue.uppercased())  \($0.id.rawValue): \($0.measured)  [need \($0.requirement)]" }
            .joined(separator: "\n")
    }

    @Test("IMG_0012 produces a compliant photo")
    func goldenCase() async throws {
        let spec = try Self.spec()
        let image = try Self.image("IMG_0012.HEIC")
        let result = await PassportPipeline().run(image, spec: spec)

        print("""
        GOLDEN CASE IMG_0012
          verdict: \(result.verdict)
          reason : \(result.failureReason ?? "-")
          input checks:
        \(Self.describe(result.inputChecks))
          output checks:
        \(Self.describe(result.outputChecks))
        """)

        if let output = result.output {
            Self.write(output.digital, named: "IMG_0012_digital.png")
            if let sheet = output.printSheet { Self.write(sheet, named: "IMG_0012_sheet.png") }
            print("  crown \(output.crownY)  chin \(output.chinY)  head \(output.headHeightPx) px")
            print("  jpeg \(output.digitalSizeKB) KB")
        }

        let output = try #require(result.output, "pipeline produced no output")

        // Ground truth from fixtures/expected.json, in source pixels before levelling. Levelling
        // rotates by ~2 deg about the eye midpoint, which moves these a little, so the tolerance
        // is wider than the manifest's 15 px.
        #expect(abs(Double(output.crownY) - 936) < 60, "crown \(output.crownY)")
        #expect(abs(Double(output.chinY) - 2736) < 60, "chin \(output.chinY)")
        #expect(abs(Double(output.headHeightPx) - 1800) < 80, "head \(output.headHeightPx)")

        #expect(output.digital.width == 630)
        #expect(output.digital.height == 810)
        #expect(output.digitalSizeKB >= 10 && output.digitalSizeKB <= 250)

        // expected.json allows only yaw and lighting to warn.
        let allowed: Set<CheckID> = [.yaw, .lighting]
        for check in result.allChecks where check.status != .pass {
            #expect(allowed.contains(check.id) && check.status == .warn,
                    "\(check.id.rawValue) was \(check.status.rawValue): \(check.measured)")
        }
        #expect(result.verdict != .cannotUse)
    }

    @Test("every fixture behaves as expected.json says")
    func allFixtures() async throws {
        let spec = try Self.spec()
        let suite = try FixtureManifestTests.loadSuite()
        let fixtures = try #require(RepoPaths.fixtures)
        var report: [String] = []
        var failures: [String] = []

        for testCase in suite.cases {
            let url = fixtures.appendingPathComponent(testCase.file)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let image = try ImageLoader.load(contentsOf: url)
            let result = await PassportPipeline().run(image, spec: spec)

            let failed = Set(result.failures.map(\.id.rawValue))
            let warned = Set(result.warnings.map(\.id.rawValue))
            report.append("\(testCase.fileName)  expect=\(testCase.expect.rawValue)  verdict=\(result.verdict)")
            report.append("    failed: \(failed.sorted().joined(separator: ", "))")
            report.append("    warned: \(warned.sorted().joined(separator: ", "))")

            switch testCase.expect {
            case .accept:
                if result.output == nil { failures.append("\(testCase.fileName): expected accept, got no output") }
            case .reject:
                let acceptable = Set((testCase.primaryReasons ?? []) + (testCase.alsoAcceptableReasons ?? []))
                if result.output != nil {
                    failures.append("\(testCase.fileName): expected reject, but a photo was produced")
                } else if failed.isDisjoint(with: acceptable) {
                    failures.append("\(testCase.fileName): rejected for \(failed.sorted()) but expected one of \(acceptable.sorted())")
                }
            case .borderline:
                break
            }

            if let output = result.output {
                Self.write(output.digital, named: "\(testCase.fileName).digital.png")
            }
        }

        print("FIXTURE PIPELINE\n" + report.joined(separator: "\n"))
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }
}
