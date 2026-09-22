import CoreGraphics
import Foundation
import ImageIO
import Testing
import TestSupport
import PhotoAnalysis
import PhotoPipeline
import SpecKit
import UniformTypeIdentifiers

/// Runs the whole pipeline over a large third-party portrait set. The fixture suite proves the
/// pipeline is right on one face; this proves it does not fall over on many.
@Suite("Calibration pipeline", .serialized, .enabled(if: RepoPaths.hasCalibrationPhotos))
struct CalibrationPipelineTests {

    struct Outcome {
        var name: String
        var verdict: String
        var failed: [String]
        var warned: [String]
        var headMM: Double?
        var seconds: Double
        var outputPath: URL?
        var reason: String?
    }

    static func runAll(spec: DocumentSpec, limit: Int = 200) async throws -> [Outcome] {
        let dir = try #require(RepoPaths.calibrationPhotos)
        let files = (try FileManager.default.contentsOfDirectory(atPath: dir.path))
            .filter { $0.lowercased().hasSuffix(".jpg") }.sorted().prefix(limit)
        let debug = URL(fileURLWithPath: "/tmp/passportkit-debug/calibration", isDirectory: true)
        try? FileManager.default.createDirectory(at: debug, withIntermediateDirectories: true)

        var outcomes: [Outcome] = []
        let geometry = SpecGeometry(spec: spec)

        for file in files {
            let url = dir.appendingPathComponent(file)
            guard let image = try? ImageLoader.load(contentsOf: url, maxPixelSize: ImageLoader.defaultMaxPixelSize)
            else { continue }

            let started = Date()
            let result = await PassportPipeline().run(image, spec: spec)
            let elapsed = Date().timeIntervalSince(started)

            var headMM: Double?
            var path: URL?
            if let output = result.output, let geometry {
                headMM = geometry.pxToMM(
                    Double(output.digital.height) * (output.chinFraction - output.crownFraction)
                )
                let out = debug.appendingPathComponent(file.replacingOccurrences(of: ".jpg", with: "_out.png"))
                if let dest = CGImageDestinationCreateWithURL(
                    out as CFURL, UTType.png.identifier as CFString, 1, nil
                ) {
                    CGImageDestinationAddImage(dest, output.digital, nil)
                    CGImageDestinationFinalize(dest)
                    path = out
                }
            }

            outcomes.append(Outcome(
                name: file,
                verdict: "\(result.verdict)",
                failed: result.failures.map(\.id.rawValue).sorted(),
                warned: result.warnings.map(\.id.rawValue).sorted(),
                headMM: headMM,
                seconds: elapsed,
                outputPath: path,
                reason: result.failureReason
            ))
        }
        return outcomes
    }

    @Test("the pipeline survives a large portrait set and reports why it refuses")
    func survivesTheSet() async throws {
        let spec = try SpecLoader.load(contentsOf: #require(RepoPaths.inPassportSpec))
        let outcomes = try await Self.runAll(spec: spec)
        #expect(outcomes.count >= 50, "only \(outcomes.count) portraits ran")

        let accepted = outcomes.filter { $0.outputPath != nil }
        var reasons: [String: Int] = [:]
        for outcome in outcomes where outcome.outputPath == nil {
            for reason in outcome.failed.isEmpty ? ["(threw)"] : outcome.failed {
                reasons[reason, default: 0] += 1
            }
        }

        let clean = outcomes.filter { $0.outputPath != nil && $0.failed.isEmpty }
        var lines = ["ran \(outcomes.count), rendered \(accepted.count), fully clean \(clean.count)"]
        for outcome in accepted {
            lines.append("  rendered \(outcome.name): verdict \(outcome.verdict) failed \(outcome.failed) warned \(outcome.warned)")
        }
        lines.append("rejection reasons (a photo can have several):")
        for (reason, count) in reasons.sorted(by: { $0.value > $1.value }) {
            lines.append(String(format: "  %-18@ %d", reason as NSString, count))
        }
        let times = outcomes.map(\.seconds).sorted()
        lines.append(String(format: "seconds: p50 %.2f  p90 %.2f  max %.2f",
                            times[times.count / 2],
                            times[min(times.count - 1, Int(Double(times.count) * 0.9))],
                            times.last ?? 0))
        if !accepted.isEmpty {
            let heads = accepted.compactMap(\.headMM).sorted()
            lines.append(String(format: "head mm on accepted: min %.2f  max %.2f", heads.first ?? 0, heads.last ?? 0))
        }
        var thrownCounts: [String: Int] = [:]
        for outcome in outcomes where outcome.failed.isEmpty && outcome.outputPath == nil {
            thrownCounts[outcome.reason ?? "(no reason)", default: 0] += 1
        }
        if !thrownCounts.isEmpty {
            let noFace = outcomes.filter { $0.failed.isEmpty && $0.outputPath == nil }.map(\.name)
            lines.append("NOFACE " + noFace.joined(separator: " "))
            lines.append("thrown reasons:")
            for (reason, count) in thrownCounts.sorted(by: { $0.value > $1.value }) {
                lines.append("  \(count)x  \(reason)")
            }
        }
        print("CALIBRATION PIPELINE\n" + lines.joined(separator: "\n"))

        // The contract: never crash, and every refusal is explained.
        for outcome in outcomes where outcome.outputPath == nil {
            #expect(!outcome.failed.isEmpty || outcome.verdict == "cannotUse",
                    "\(outcome.name) refused with no reason")
        }
    }

    /// Every photo the pipeline accepts must actually meet the spec it was measured against.
    /// An accepted photo that is out of spec is far worse than a rejection.
    @Test("nothing is accepted that misses its own head-height band")
    func acceptedOutputsAreInSpec() async throws {
        let spec = try SpecLoader.load(contentsOf: #require(RepoPaths.inPassportSpec))
        let band = try #require(HeadHeightBand.inMM(spec: spec))
        let outcomes = try await Self.runAll(spec: spec)

        var offenders: [String] = []
        for outcome in outcomes where outcome.outputPath != nil {
            guard let headMM = outcome.headMM else { continue }
            if headMM < band.min || headMM > band.max {
                offenders.append(String(format: "%@ head %.2f mm", outcome.name, headMM))
            }
        }
        let report = "accepted but out of spec:\n" + offenders.joined(separator: "\n")
        #expect(offenders.isEmpty, "\(report)")
    }
}
