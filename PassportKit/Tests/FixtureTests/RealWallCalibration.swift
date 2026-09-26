import CoreGraphics
import Foundation
import SpecKit
import Testing
import TestSupport
@testable import PhotoAnalysis
@testable import PhotoPipeline

@Suite("Real wall calibration", .serialized, .enabled(if: RepoPaths.hasFixturePhotos))
struct RealWallCalibration {
    @Test("what a real wall measures in an unedited photo")
    func measure() async throws {
        let dir = try #require(RepoPaths.fixtures).appendingPathComponent("photos")
        let specDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("specs")
        let spec = try SpecLoader.load(contentsOf: specDir.appendingPathComponent("us-passport.json"))
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { ["heic", "jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let pipeline = PassportPipeline()
        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let image = try? ImageLoader.load(data: data) else { continue }
            let result = await pipeline.run(image, spec: spec, mode: .keep)
            guard let out = result.output?.digital,
                  let px = ImageConversion.pixelImage(from: out) else { continue }

            // The top band, excluding the middle where the head is.
            var samples: [Int] = []
            let band = max(1, px.height / 6)
            for y in stride(from: 0, to: band, by: 2) {
                for x in stride(from: 0, to: px.width, by: 2) {
                    let p = px.offset(x: x, y: y)
                    samples.append(Int(min(px.pixels[p], min(px.pixels[p + 1], px.pixels[p + 2]))))
                }
            }
            let sorted = samples.sorted()
            guard !sorted.isEmpty else { continue }
            let median = sorted[sorted.count / 2]
            let p05 = sorted[sorted.count / 20]
            let p95 = sorted[sorted.count - 1 - sorted.count / 20]
            print(String(format: "WALL %@ median %3d  p05 %3d  p95 %3d  spread %3d",
                         file.lastPathComponent.padding(toLength: 16, withPad: " ", startingAt: 0),
                         median, p05, p95, p95 - p05))
        }
        print("spec minChannelValue = \(spec.background?.minChannelValue ?? 245)")
    }
}
