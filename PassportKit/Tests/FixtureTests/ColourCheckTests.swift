import CoreGraphics
import Foundation
import SpecKit
import Testing
import TestSupport
@testable import PhotoAnalysis
@testable import PhotoPipeline

/// Every authority in the app requires a colour photo. Before this check a greyscale scan passed
/// every other rule and earned a green "meets requirements" (LESSONS 27's shape).
@Suite("Colour photo", .serialized, .enabled(if: RepoPaths.hasFixturePhotos))
struct ColourCheckTests {

    static func desaturated(_ image: PixelImage) -> PixelImage {
        var out = image
        for i in 0..<(out.width * out.height) {
            let r: Double = Double(out.pixels[i * 4])
            let g: Double = Double(out.pixels[i * 4 + 1])
            let b: Double = Double(out.pixels[i * 4 + 2])
            let y: Double = 0.2126 * r + 0.7152 * g + 0.0722 * b
            let level = UInt8(Swift.min(255.0, Swift.max(0.0, y)))
            out.pixels[i * 4] = level
            out.pixels[i * 4 + 1] = level
            out.pixels[i * 4 + 2] = level
        }
        return out
    }

    @Test("a colour photo passes and the same photo in black and white fails")
    func colourSeparatesFromGreyscale() async throws {
        let url = try #require(RepoPaths.fixtures).appendingPathComponent("photos/IMG_0012.HEIC")
        let image = try ImageLoader.load(data: try Data(contentsOf: url), maxPixelSize: 1200)
        let face = try await VisionFaceAnalyzer().analyze(image)
        let pixels = try #require(ImageConversion.pixelImage(from: image))

        let colour = try #require(ImageMetrics.faceSaturation(pixels, face: face))
        let grey = try #require(ImageMetrics.faceSaturation(Self.desaturated(pixels), face: face))

        #expect(InputGate.colourCheck(colour).status == .pass, "colour read \(colour)")
        #expect(InputGate.colourCheck(grey).status == .fail, "greyscale read \(grey)")
        // The margin is what makes the threshold safe rather than lucky.
        #expect(colour - grey > 0.3, "only \(colour - grey) between colour and greyscale")
    }

    @Test("every fixture photo is comfortably above the threshold")
    func noFixtureIsNearTheThreshold() async throws {
        let dir = try #require(RepoPaths.fixtures).appendingPathComponent("photos")
        let files = try FileManager.default
            .contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { ["heic", "jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }
        let analyzer = VisionFaceAnalyzer()
        var measured = 0
        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let image = try? ImageLoader.load(data: data, maxPixelSize: 1000),
                  let face = try? await analyzer.analyze(image),
                  let pixels = ImageConversion.pixelImage(from: image) else { continue }
            guard let value = ImageMetrics.faceSaturation(pixels, face: face) else { continue }
            #expect(
                value > InputGate.minFaceSaturation * 3,
                "\(file.lastPathComponent) reads \(value), too close to the threshold"
            )
            measured += 1
        }
        #expect(measured >= 10)
    }

    /// End to end: the pipeline must refuse it, not just the metric.
    @Test("the pipeline rejects a black and white photo outright")
    func pipelineRejectsGreyscale() async throws {
        let url = try #require(RepoPaths.fixtures).appendingPathComponent("photos/IMG_0012.HEIC")
        let image = try ImageLoader.load(data: try Data(contentsOf: url), maxPixelSize: 2400)
        let pixels = try #require(ImageConversion.pixelImage(from: image))
        let grey = try #require(ImageConversion.cgImage(from: Self.desaturated(pixels)))
        let spec = try SpecLoader.load(contentsOf: #require(RepoPaths.inPassportSpec))

        let result = await PassportPipeline().run(grey, spec: spec)
        #expect(result.verdict == .cannotUse)
        #expect(result.output == nil, "a black and white photo was still rendered for saving")
        let colour = try #require(
            result.inputChecks.first { $0.id == .colour }, "no colour check ran"
        )
        #expect(colour.status == .fail)
        #expect(colour.userMessage?.isEmpty == false)
    }

    /// Degenerate landmarks reach Int conversions here too (LESSONS 32).
    @Test("degenerate landmarks do not trap the saturation metric")
    func degenerateFacesAreSafe() throws {
        let image = PixelImage(width: 40, height: 40, fill: (200, 150, 120))
        var face = FaceMeasurements(
            faceCount: 1, boundingBox: .init(x: 5, y: 5, width: 20, height: 20),
            leftEye: .init(x: 12, y: 15), rightEye: .init(x: 24, y: 15),
            contour: (0..<12).map { i in
                let t = Double(i) / 12 * 2 * .pi
                return CGPoint(x: 18 + cos(t) * 9, y: 18 + sin(t) * 11)
            },
            rawChin: .init(x: 18, y: 30), browY: 10,
            yawDeg: 0, pitchDeg: 0, rollDeg: 0,
            captureQuality: nil, eyeOpenness: 0.3, mouthOpenness: 0.02
        )
        let measurable = try #require(ImageMetrics.faceSaturation(image, face: face))
        #expect(measurable > 0)

        // An unmeasurable face must read as nil, never as 0 - 0 would be indistinguishable from
        // grey and would reject a perfectly good colour photo.
        for value in [Double.nan, .infinity, -.infinity, 1e300, -1e300] {
            face.rawChin = .init(x: value, y: value)
            #expect(ImageMetrics.faceSaturation(image, face: face) == nil)
            face.browY = value
            #expect(ImageMetrics.faceSaturation(image, face: face) == nil)
        }
    }

    /// The check must be skipped rather than failed when saturation cannot be measured.
    @Test("an unmeasurable face produces no colour check at all")
    func unmeasurableProducesNoCheck() throws {
        let spec = try SpecLoader.load(contentsOf: #require(RepoPaths.inPassportSpec))
        let face = FaceMeasurements(
            faceCount: 1, boundingBox: .init(x: 5, y: 5, width: 20, height: 20),
            leftEye: .init(x: 12, y: 15), rightEye: .init(x: 24, y: 15),
            contour: [], rawChin: .init(x: 18, y: 30), browY: 10,
            yawDeg: 0, pitchDeg: 0, rollDeg: 0,
            captureQuality: nil, eyeOpenness: 0.3, mouthOpenness: 0.02
        )
        let checks = InputGate.evaluate(
            face: face, sharpness: 100, cheekImbalance: 0.01, faceSaturation: nil,
            headHeightPx: 900, imageSize: .init(width: 800, height: 1000), spec: spec
        )
        #expect(!checks.contains { $0.id == .colour })
    }
}
