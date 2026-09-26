import CoreGraphics
import Foundation
import SpecKit
import Testing
import TestSupport
@testable import PhotoAnalysis
@testable import PhotoPipeline

/// Measures the defect the owner reported: background-coloured speckles punched INTO the hair.
///
/// A hole is a background-coloured pixel that is NOT reachable from the outer background. Real
/// background is one connected region touching the top corners; anything background-coloured and
/// enclosed by subject was carved out of the person.
@Suite("Hair holes", .serialized, .enabled(if: RepoPaths.hasFixturePhotos))
struct HairHolesCalibration {

    /// Fraction of the image that is background-coloured but enclosed by subject.
    static func punchedHoleFraction(_ pixels: PixelImage, background: RGB) -> Double {
        let w = pixels.width, h = pixels.height
        guard w > 2, h > 2 else { return 0 }
        let (br, bg, bb) = background.bytes

        func isBackgroundColoured(_ i: Int) -> Bool {
            let p = i * 4
            let dr = Int(pixels.pixels[p]) - Int(br)
            let dg = Int(pixels.pixels[p + 1]) - Int(bg)
            let db = Int(pixels.pixels[p + 2]) - Int(bb)
            return dr * dr + dg * dg + db * db < 300
        }

        // Flood fill the genuine background inward from the border.
        var outside = [Bool](repeating: false, count: w * h)
        var stack: [Int] = []
        for x in 0..<w {
            for y in [0, h - 1] where isBackgroundColoured(y * w + x) {
                if !outside[y * w + x] { outside[y * w + x] = true; stack.append(y * w + x) }
            }
        }
        for y in 0..<h {
            for x in [0, w - 1] where isBackgroundColoured(y * w + x) {
                if !outside[y * w + x] { outside[y * w + x] = true; stack.append(y * w + x) }
            }
        }
        while let i = stack.popLast() {
            let x = i % w, y = i / w
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, nx < w, ny >= 0, ny < h else { continue }
                let n = ny * w + nx
                guard !outside[n], isBackgroundColoured(n) else { continue }
                outside[n] = true
                stack.append(n)
            }
        }

        var holes = 0
        for i in 0..<(w * h) where isBackgroundColoured(i) && !outside[i] { holes += 1 }
        return Double(holes) / Double(w * h)
    }

    /// Pins the level after the LESSONS 37 fix: worst measured 0.0157%, down from 0.0239%.
    /// Rim cleanup now requires a pixel to sit in a backdrop REGION before clearing it, so a
    /// highlight on a strand of hair is no longer mistaken for wall.
    @Test("punched holes stay at or below the level we have measured")
    func holesDoNotGetWorse() async throws {
        let dir = try #require(RepoPaths.fixtures).appendingPathComponent("photos")
        let spec = try SpecLoader.load(contentsOf: #require(RepoPaths.inPassportSpec))
        let background = RGB(hex: spec.background?.colorHex ?? "#FFFFFF") ?? .white
        let files = try FileManager.default
            .contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { ["heic", "jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let pipeline = PassportPipeline()
        var worst = 0.0
        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let image = try? ImageLoader.load(data: data) else { continue }
            let result = await pipeline.run(image, spec: spec)
            guard let out = result.output?.digital,
                  let pixels = ImageConversion.pixelImage(from: out) else { continue }
            let holes = Self.punchedHoleFraction(pixels, background: background)
            let integrity = result.outputChecks.first { $0.id == .faceIntegrity }?.measured ?? "-"
            worst = max(worst, holes)
            print(String(format: "HOLES %@  %.4f%%   faceIntegrity %@",
                         file.lastPathComponent.padding(toLength: 16, withPad: " ", startingAt: 0),
                         holes * 100, integrity))
        }
        print(String(format: "WORST %.4f%%", worst * 100))
        // Headroom over the measured 0.0157%, tight enough to catch a real regression.
        #expect(worst < 0.0004, "punched holes got worse: \(worst * 100)%")
    }
}
