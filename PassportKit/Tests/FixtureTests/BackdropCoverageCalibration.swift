import Foundation
import SpecKit
import Testing
import TestSupport
@testable import PhotoAnalysis
@testable import PhotoPipeline

@Suite("Backdrop coverage calibration", .serialized, .enabled(if: RepoPaths.hasFixturePhotos))
struct BackdropCoverageCalibration {
    @Test("how much of a good output is backdrop")
    func measure() async throws {
        let dir = try #require(RepoPaths.fixtures).appendingPathComponent("photos")
        let specDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("specs")
        let checker = ComplianceChecker(
            analyzer: VisionFaceAnalyzer(), segmenter: VisionSubjectSegmenter()
        )
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { ["heic","jpg","jpeg","png"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for name in ["in-passport", "us-passport", "gb-passport"] {
            let spec = try SpecLoader.load(contentsOf: specDir.appendingPathComponent("\(name).json"))
            let minimum = UInt8(spec.background?.minChannelValue ?? 245)
            for file in files {
                guard let data = try? Data(contentsOf: file),
                      let image = try? ImageLoader.load(data: data) else { continue }
                let result = await PassportPipeline().run(image, spec: spec, mode: .replace)
                guard let out = result.output?.digital,
                      let px = ImageConversion.pixelImage(from: out) else { continue }
                let region = checker.backdropRegion(px, minimum: minimum)
                let covered = region.filter { $0 }.count
                let fraction = Double(covered) / Double(px.width * px.height)
                print(String(format: "COVER %@ %@  %.1f%%", name.padding(toLength: 12, withPad: " ", startingAt: 0),
                             file.lastPathComponent.padding(toLength: 16, withPad: " ", startingAt: 0), fraction * 100))
            }
        }
    }
}
