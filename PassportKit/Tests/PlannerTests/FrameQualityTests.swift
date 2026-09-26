import CoreGraphics
import Foundation
import SpecKit
import Testing
import TestSupport
@testable import PhotoAnalysis
@testable import PhotoPipeline

/// Background and lighting judged live, so the person can still move. Built on synthetic walls
/// where the right answer is known by construction.
@Suite("Live frame quality")
struct FrameQualityTests {

    static let size = CGSize(width: 300, height: 400)

    static func face() -> FaceMeasurements {
        let w = size.width, h = size.height
        return FaceMeasurements(
            faceCount: 1,
            boundingBox: CGRect(x: w * 0.33, y: h * 0.2, width: w * 0.34, height: h * 0.42),
            leftEye: CGPoint(x: w * 0.43, y: h * 0.35),
            rightEye: CGPoint(x: w * 0.57, y: h * 0.35),
            contour: (0..<24).map { i in
                let t = Double(i) / 24 * 2 * .pi
                return CGPoint(x: w * 0.5 + cos(t) * w * 0.17, y: h * 0.40 + sin(t) * h * 0.21)
            },
            rawChin: CGPoint(x: w * 0.5, y: h * 0.61), browY: h * 0.27,
            yawDeg: 0, pitchDeg: 0, rollDeg: 0,
            captureQuality: 0.9, eyeOpenness: 0.3, mouthOpenness: 0.02
        )
    }

    /// A wall of one tone, with a head-shaped blob in the middle so the sampler has to exclude it.
    static func scene(wall: UInt8, stripes: Bool = false, headTone: UInt8 = 90) -> PixelImage {
        let w = Int(size.width), h = Int(size.height)
        var image = PixelImage(width: w, height: h, fill: (wall, wall, wall))
        if stripes {
            for y in 0..<h {
                for x in 0..<w where (x / 12) % 2 == 0 {
                    let o = image.offset(x: x, y: y)
                    // A door frame or a picture on the wall: large, hard-edged tonal blocks.
                    image.pixels[o] = 40; image.pixels[o + 1] = 40; image.pixels[o + 2] = 40
                }
            }
        }
        let f = face()
        for y in 0..<h {
            for x in 0..<w {
                let dx = (Double(x) - Double(f.eyeMidpoint.x)) / (Double(size.width) * 0.18)
                let dy = (Double(y) - Double(f.eyeMidpoint.y)) / (Double(size.height) * 0.22)
                guard dx * dx + dy * dy <= 1 else { continue }
                let o = image.offset(x: x, y: y)
                image.pixels[o] = headTone
                image.pixels[o + 1] = headTone
                image.pixels[o + 2] = headTone
            }
        }
        return image
    }

    static func read(_ image: PixelImage) -> FrameQuality.Reading {
        FrameQuality.assess(
            image: image, luminance: ImageConversion.luminance(of: image), face: face()
        )
    }

    @Test("a plain light wall reads bright and plain")
    func plainWall() {
        let reading = Self.read(Self.scene(wall: 235))
        #expect(reading.isUsable)
        #expect(reading.backgroundBrightness > FrameQuality.darkBackgroundBelow)
        #expect(reading.backgroundVariation < FrameQuality.busyBackgroundAbove)
    }

    @Test("a dark wall is flagged as too dark")
    func darkWall() {
        let reading = Self.read(Self.scene(wall: 70))
        #expect(reading.isUsable)
        #expect(reading.backgroundBrightness < FrameQuality.darkBackgroundBelow)
    }

    @Test("a patterned wall reads as more varied than a plain one")
    func busyWall() {
        let busy = Self.read(Self.scene(wall: 235, stripes: true))
        let plain = Self.read(Self.scene(wall: 235))
        #expect(plain.backgroundVariation < busy.backgroundVariation)
    }

    /// The head is not the wall. If the sampler included it, a dark-haired person in front of a
    /// white wall would be told to find a plainer one.
    @Test("the head is excluded from the wall samples")
    func headIsNotTheWall() {
        let darkHead = Self.read(Self.scene(wall: 240, headTone: 10))
        let lightHead = Self.read(Self.scene(wall: 240, headTone: 200))
        #expect(abs(darkHead.backgroundBrightness - lightHead.backgroundBrightness) < 0.02)
        #expect(darkHead.backgroundVariation < FrameQuality.busyBackgroundAbove)
    }

    @Test("a frame with nothing measurable says so instead of guessing")
    func unusableFrames() {
        let tiny = PixelImage(width: 4, height: 4, fill: (255, 255, 255))
        let reading = FrameQuality.assess(
            image: tiny, luminance: ImageConversion.luminance(of: tiny), face: Self.face()
        )
        #expect(!reading.isUsable)
    }

    /// Degenerate landmarks reach Int conversions and array indices here too (LESSONS 24/32).
    @Test("degenerate or huge landmarks do not trap")
    func degenerateFacesAreSafe() {
        let image = Self.scene(wall: 220)
        let luminance = ImageConversion.luminance(of: image)
        for value in [CGFloat.nan, .infinity, -.infinity, 1e300, -1e300, 0] {
            var f = Self.face()
            f.rawChin = CGPoint(x: value, y: value)
            _ = FrameQuality.assess(image: image, luminance: luminance, face: f)
            f = Self.face(); f.browY = value
            _ = FrameQuality.assess(image: image, luminance: luminance, face: f)
            f = Self.face(); f.contour = []
            _ = FrameQuality.assess(image: image, luminance: luminance, face: f)
        }
    }

    // MARK: cues

    static func spec() throws -> DocumentSpec {
        try SpecLoader.load(contentsOf: #require(RepoPaths.inPassportSpec))
    }

    static func cues(_ reading: FrameQuality.Reading, spec: DocumentSpec) -> [CaptureCue] {
        CaptureGuidance.assess(
            face: face(), headHeightPx: Double(size.height) * 0.62, cheekImbalance: nil,
            quality: reading, frameSize: size, spec: spec
        ).cues
    }

    @Test("a dark wall is called out during capture, not after")
    func darkWallCue() throws {
        let cues = Self.cues(Self.read(Self.scene(wall: 70)), spec: try Self.spec())
        #expect(cues.contains { $0.kind == .darkBackground })
        // Advisory: the pipeline replaces the background, so this must not block the shutter.
        #expect(cues.first { $0.kind == .darkBackground }?.isBlocking == false)
    }

    /// The busy-wall metric does not separate on real photos, so it must stay silent. The first
    /// threshold tried here would have nagged 13 of the 14 real fixture photos.
    @Test("a busy wall says nothing, because the metric does not separate on real photos")
    func busyWallIsSilent() throws {
        let cues = Self.cues(Self.read(Self.scene(wall: 235, stripes: true)), spec: try Self.spec())
        #expect(!cues.contains { $0.kind == .busyBackground })
    }

    @Test("a good wall produces no background nagging")
    func goodWallIsQuiet() throws {
        let cues = Self.cues(Self.read(Self.scene(wall: 235)), spec: try Self.spec())
        #expect(!cues.contains { $0.kind == .darkBackground || $0.kind == .busyBackground })
    }

    @Test("uneven lighting is called out during capture")
    func lightingCue() throws {
        let spec = try Self.spec()
        let limit = try #require(spec.lighting?.cheekImbalance?.failAbove)
        let reading = FrameQuality.Reading(
            backgroundBrightness: 0.9, backgroundVariation: 0.01,
            cheekImbalance: limit + 0.05, isUsable: true
        )
        #expect(Self.cues(reading, spec: spec).contains { $0.kind == .lighting })
    }

    /// Nothing measurable must mean silence, not a guess.
    @Test("an unusable reading produces no background cues at all")
    func unusableReadingIsSilent() throws {
        let cues = Self.cues(.unusable, spec: try Self.spec())
        #expect(!cues.contains {
            $0.kind == .darkBackground || $0.kind == .busyBackground
        })
    }
}
