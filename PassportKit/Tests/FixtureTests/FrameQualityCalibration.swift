import Foundation
import Testing
import TestSupport
@testable import PhotoAnalysis
@testable import PhotoPipeline

/// The capture cues are advice given to someone who is standing still trying to get this right.
/// A cue that fires on a photo that actually works is worse than no cue, so the thresholds are
/// pinned against the real fixture photos rather than against synthetic walls.
@Suite("Frame quality calibration", .enabled(if: RepoPaths.hasFixturePhotos))
struct FrameQualityCalibration {

    static func readings() async throws -> [(name: String, reading: FrameQuality.Reading)] {
        let dir = try #require(RepoPaths.fixtures).appendingPathComponent("photos")
        let files = try FileManager.default
            .contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { ["heic", "jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let analyzer = VisionFaceAnalyzer()
        var out: [(String, FrameQuality.Reading)] = []
        for file in files {
            guard let data = try? Data(contentsOf: file),
                  // The live path measures a downscaled frame, so measure one here too.
                  let image = try? ImageLoader.load(data: data, maxPixelSize: 1200),
                  let face = try? await analyzer.analyze(image),
                  let pixels = ImageConversion.pixelImage(from: image) else { continue }
            let luminance = ImageConversion.luminance(of: pixels)
            out.append((
                file.lastPathComponent,
                FrameQuality.assess(image: pixels, luminance: luminance, face: face)
            ))
        }
        return out
    }

    @Test("every real photo is measurable")
    func allMeasurable() async throws {
        let readings = try await Self.readings()
        #expect(readings.count >= 10, "only \(readings.count) fixtures measured")
        for (name, reading) in readings {
            #expect(reading.isUsable, "\(name) produced no wall samples")
        }
    }

    /// These are genuine attempts at a passport photo. None of them should be told the wall is
    /// too dark, whatever the verdict on the photo itself turns out to be.
    @Test("no real attempt is nagged about a dark background")
    func noFalseDarkBackgroundCues() async throws {
        for (name, reading) in try await Self.readings() {
            #expect(
                reading.backgroundBrightness >= FrameQuality.darkBackgroundBelow,
                "\(name) would be told to find a lighter wall: \(reading.backgroundBrightness)"
            )
        }
    }

    /// The margin that makes the threshold defensible. If a future change narrows this, the
    /// threshold was moved without re-measuring.
    @Test("the dark threshold keeps real margin under the worst real photo")
    func darkThresholdHasMargin() async throws {
        let darkest = try await Self.readings()
            .map(\.reading.backgroundBrightness).min() ?? 0
        #expect(
            darkest - FrameQuality.darkBackgroundBelow > 0.05,
            "only \(darkest - FrameQuality.darkBackgroundBelow) of margin under the darkest real photo"
        )
    }

    /// Documents why the busy-wall cue is not shipped: on real photos the metric spans almost
    /// its whole range, so no threshold separates a patterned wall from a plain one.
    @Test("background variation does not separate on real photos")
    func variationDoesNotSeparate() async throws {
        let values = try await Self.readings().map(\.reading.backgroundVariation)
        let spread = (values.max() ?? 0) - (values.min() ?? 0)
        #expect(
            spread > 0.25,
            "variation now separates (spread \(spread)); re-evaluate whether a cue is worth shipping"
        )
    }
}
