import CoreGraphics
import Foundation
import Testing
import TestSupport
import PhotoAnalysis
import SpecKit

/// LESSONS 5: the cheek metric is fragile, the same photo scored 2% or 11% under two patch
/// placements. These tests pin the placement against the reference pipeline's numbers and,
/// more importantly, against the decisions the manifest requires.
/// Serialized: each case decodes a 24 MP photo into full-size pixel and luminance buffers, and
/// running them in parallel exhausts memory.
@Suite("Lighting calibration", .serialized, .enabled(if: RepoPaths.hasFixturePhotos))
struct LightingCalibrationTests {

    static func imbalance(_ name: String) async throws -> Double {
        let url = try #require(RepoPaths.fixtures).appendingPathComponent("photos/\(name)")
        let image = try ImageLoader.load(contentsOf: url)
        let face = try await VisionFaceAnalyzer().analyze(image)
        let pixels = try #require(ImageConversion.pixelImage(from: image))
        let luminance = ImageConversion.luminance(of: pixels)
        return ImageMetrics.cheekImbalance(luminance: luminance, face: face)
    }

    @Test("cheek imbalance across every fixture, against the reference values")
    func table() async throws {
        let reference: [(String, Double)] = [
            ("IMG_0012.HEIC", 0.089), ("IMG_0010.HEIC", 0.126), ("IMG_0009.HEIC", 0.043),
            ("IMG_0011.HEIC", 0.130), ("IMG_0015.HEIC", 0.072), ("IMG_0016.HEIC", 0.138),
            ("IMG_0004.HEIC", 0.130), ("IMG_0005.HEIC", 0.099), ("IMG_0006.HEIC", 0.022),
            ("IMG_0007.HEIC", 0.091), ("webcam.jpg", 0.468), ("IMG_0008.HEIC", 0.082),
            ("IMG_0013.HEIC", 0.110), ("IMG_0014.HEIC", 0.119),
        ]
        var lines: [String] = ["file                 ours   python"]
        for (name, python) in reference {
            let ours = try await Self.imbalance(name)
            lines.append(String(format: "%-20@ %.3f  %.3f", name as NSString, ours, python))
        }
        print("CHEEK IMBALANCE\n" + lines.joined(separator: "\n"))
    }

    /// The two decisions the manifest actually forces. Everything else is diagnosis.
    @Test("IMG_0012 must not be rejected for lighting")
    func goldenCasePasses() async throws {
        let spec = try SpecLoader.load(contentsOf: #require(RepoPaths.inPassportSpec))
        let failAbove = try #require(spec.lighting?.cheekImbalance?.failAbove)
        let value = try await Self.imbalance("IMG_0012.HEIC")
        #expect(value < failAbove, "IMG_0012 lighting \(value) would fail (limit \(failAbove))")
    }

    @Test("IMG_0010 must be rejected for lighting")
    func sideLitIsRejected() async throws {
        let spec = try SpecLoader.load(contentsOf: #require(RepoPaths.inPassportSpec))
        let failAbove = try #require(spec.lighting?.cheekImbalance?.failAbove)
        let value = try await Self.imbalance("IMG_0010.HEIC")
        #expect(value > failAbove, "IMG_0010 lighting \(value) would pass (limit \(failAbove))")
    }

    @Test("the webcam shot is clearly worst")
    func webcamIsWorst() async throws {
        let webcam = try await Self.imbalance("webcam.jpg")
        let golden = try await Self.imbalance("IMG_0012.HEIC")
        #expect(webcam > golden * 2)
    }
}
