import CoreGraphics
import Foundation
import Testing
import TestSupport
import PhotoAnalysis
import PhotoPipeline
import SpecKit

/// `GateCalibration`'s thresholds were set from one person's face. These measure a wider set of
/// portraits so the numbers can be judged against a distribution rather than a single photo.
/// The photos are third-party and gitignored, so this suite skips on a clean clone.
@Suite("Threshold calibration", .serialized, .enabled(if: RepoPaths.hasCalibrationPhotos))
struct ThresholdCalibrationTests {

    struct Measurement {
        var name: String
        var mouth: Double
        var eyes: Double
        var cheek: Double
        var yaw: Double
        var pitch: Double
        var quality: Double
    }

    static func measureAll() async throws -> [Measurement] {
        let dir = try #require(RepoPaths.calibrationPhotos)
        let files = (try FileManager.default.contentsOfDirectory(atPath: dir.path))
            .filter { $0.lowercased().hasSuffix(".jpg") }.sorted()
        var out: [Measurement] = []

        for file in files {
            let url = dir.appendingPathComponent(file)
            guard let image = try? ImageLoader.load(contentsOf: url, maxPixelSize: 2000),
                  let face = try? await VisionFaceAnalyzer().analyze(image),
                  let pixels = ImageConversion.pixelImage(from: image) else { continue }
            let luminance = ImageConversion.luminance(of: pixels)
            out.append(Measurement(
                name: file,
                mouth: face.mouthOpenness,
                eyes: face.eyeOpenness,
                cheek: ImageMetrics.cheekImbalance(luminance: luminance, face: face),
                yaw: face.yawDeg,
                pitch: face.pitchDeg,
                quality: face.captureQuality ?? -1
            ))
        }
        return out
    }

    @Test("measure every calibration portrait and print the distribution")
    func distribution() async throws {
        let measurements = try await Self.measureAll()
        #expect(measurements.count >= 10, "only \(measurements.count) faces measured")

        var lines = ["file                     mouth   eyes   cheek     yaw  quality"]
        for m in measurements.sorted(by: { $0.mouth < $1.mouth }) {
            var line = m.name.padding(toLength: 24, withPad: " ", startingAt: 0)
            line += String(format: " %.3f  %.3f  %.3f  %+6.1f  %.2f",
                           m.mouth, m.eyes, m.cheek, m.yaw, m.quality)
            lines.append(line)
        }

        func summary(_ label: String, _ values: [Double]) -> String {
            let sorted = values.sorted()
            let median = sorted[sorted.count / 2]
            return String(format: "%@ min %.3f  p50 %.3f  p90 %.3f  max %.3f",
                          label, sorted.first ?? 0, median,
                          sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.9))],
                          sorted.last ?? 0)
        }
        lines.append("")
        lines.append(summary("mouth ", measurements.map(\.mouth)))
        lines.append(summary("eyes  ", measurements.map(\.eyes)))
        lines.append(summary("cheek ", measurements.map(\.cheek)))

        // How many of these ordinary portraits would the current gate reject?
        let calibration = GateCalibration.default
        let mouthRejects = measurements.filter { $0.mouth > calibration.mouthFailAbove }
        let eyeRejects = measurements.filter { $0.eyes < calibration.minEyeOpenness }
        lines.append("")
        let warned = measurements.filter {
            $0.mouth > calibration.mouthWarnAbove && $0.mouth <= calibration.mouthFailAbove
        }
        lines.append("mouthClosed FAIL > \(calibration.mouthFailAbove): \(mouthRejects.count)/\(measurements.count)")
        lines.append("mouthClosed WARN > \(calibration.mouthWarnAbove): \(warned.count)/\(measurements.count)")
        lines.append("  " + mouthRejects.map { "\($0.name) \(String(format: "%.3f", $0.mouth))" }.joined(separator: ", "))
        lines.append("eyesOpen < \(calibration.minEyeOpenness): \(eyeRejects.count)/\(measurements.count) rejected")
        lines.append("  " + eyeRejects.map { "\($0.name) \(String(format: "%.3f", $0.eyes))" }.joined(separator: ", "))

        print("CALIBRATION\n" + lines.joined(separator: "\n"))
    }
}
