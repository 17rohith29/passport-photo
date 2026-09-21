import CoreGraphics
import Foundation
import Testing
import TestSupport
import PhotoAnalysis
import PhotoPipeline
import SpecKit

/// Adversarial input that needs no private photos, so it runs on any clone. The contract is
/// narrow and absolute: the pipeline always returns, never crashes, and never emits a passport
/// photo from something that is not a usable portrait.
@Suite("Bad input", .serialized)
struct BadInputTests {

    static func spec() throws -> DocumentSpec {
        try SpecLoader.load(contentsOf: #require(RepoPaths.inPassportSpec))
    }

    static func solid(width: Int, height: Int, grey: UInt8) -> CGImage {
        var image = PixelImage(width: width, height: height, fill: (grey, grey, grey))
        image.pixels.withUnsafeMutableBytes { _ in }
        return ImageConversion.cgImage(from: image)!
    }

    static func noise(width: Int, height: Int, seed: UInt64 = 42) -> CGImage {
        var generator = SystemRandomNumberGenerator()
        _ = generator
        var state = seed
        var image = PixelImage(width: width, height: height, fill: (0, 0, 0))
        for i in 0..<(width * height) {
            // xorshift, so the image is deterministic across runs.
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            let value = UInt8(truncatingIfNeeded: state)
            image.pixels[i * 4] = value
            image.pixels[i * 4 + 1] = value &* 3
            image.pixels[i * 4 + 2] = value &* 7
            image.pixels[i * 4 + 3] = 255
        }
        return ImageConversion.cgImage(from: image)!
    }

    @Test("a blank wall is rejected, not turned into a passport photo")
    func blankImage() async throws {
        let result = await PassportPipeline().run(Self.solid(width: 1200, height: 1600, grey: 240),
                                                  spec: try Self.spec())
        #expect(result.output == nil)
        #expect(result.verdict == .cannotUse)
        #expect(result.failureReason != nil)
    }

    @Test("pure noise is rejected")
    func noiseImage() async throws {
        let result = await PassportPipeline().run(Self.noise(width: 1200, height: 1600),
                                                  spec: try Self.spec())
        #expect(result.output == nil)
        #expect(result.verdict == .cannotUse)
    }

    @Test("a tiny image is rejected rather than upscaled")
    func tinyImage() async throws {
        let result = await PassportPipeline().run(Self.solid(width: 32, height: 32, grey: 200),
                                                  spec: try Self.spec())
        #expect(result.output == nil)
        // Never upscale (LESSONS 3): nothing 32 px wide may produce a 630x810 photo.
        #expect(result.verdict == .cannotUse)
    }

    @Test("extreme aspect ratios do not crash")
    func extremeAspect() async throws {
        for size in [(2000, 10), (10, 2000), (1, 1)] {
            let result = await PassportPipeline().run(
                Self.solid(width: size.0, height: size.1, grey: 180), spec: try Self.spec()
            )
            #expect(result.output == nil, "\(size) produced output")
        }
    }

    @Test("every spec handles bad input the same way")
    func allSpecsRejectJunk() async throws {
        for url in [RepoPaths.inPassportSpec, RepoPaths.usPassportSpec, RepoPaths.squareTestSpec] {
            let spec = try SpecLoader.load(contentsOf: #require(url))
            let result = await PassportPipeline().run(Self.noise(width: 900, height: 1200), spec: spec)
            #expect(result.output == nil, "\(spec.id) produced output from noise")
            #expect(result.verdict == .cannotUse)
        }
    }

    @Test("unreadable bytes fail with a message, not a crash")
    func corruptData() throws {
        #expect(throws: (any Error).self) {
            _ = try ImageLoader.load(data: Data([0xFF, 0xD8, 0xFF, 0x00, 0x01]))
        }
        #expect(throws: (any Error).self) { _ = try ImageLoader.load(data: Data()) }
    }

    @Test("a rejection always says what was measured and what was needed")
    func rejectionsAreExplained() async throws {
        let result = await PassportPipeline().run(Self.noise(width: 900, height: 1200),
                                                  spec: try Self.spec())
        // Either a failed check with full detail, or a plain-language reason. Never neither.
        if result.failures.isEmpty {
            #expect(result.failureReason?.isEmpty == false)
        } else {
            for failure in result.failures {
                #expect(!failure.measured.isEmpty)
                #expect(!failure.requirement.isEmpty)
            }
        }
    }
}

/// Bad portraits built from the owner's real photos.
@Suite("Bad portraits", .serialized, .enabled(if: RepoPaths.hasFixturePhotos))
struct BadPortraitTests {

    static func spec() throws -> DocumentSpec {
        try SpecLoader.load(contentsOf: #require(RepoPaths.inPassportSpec))
    }

    @Test("two people in the frame is rejected for faceCount")
    func twoFaces() async throws {
        let source = try ImageLoader.load(contentsOf: #require(RepoPaths.fixtures)
            .appendingPathComponent("photos/IMG_0012.HEIC"))
        let single = try #require(ImageConversion.pixelImage(from: source))

        // Side-by-side copies, so Vision sees two faces of equal size.
        var doubled = PixelImage(width: single.width * 2, height: single.height, fill: (255, 255, 255))
        for y in 0..<single.height {
            for x in 0..<single.width {
                let from = single.offset(x: x, y: y)
                for (dx, _) in [(0, 0), (single.width, 0)] {
                    let to = doubled.offset(x: x + dx, y: y)
                    for c in 0..<4 { doubled.pixels[to + c] = single.pixels[from + c] }
                }
            }
        }
        let image = try #require(ImageConversion.cgImage(from: doubled))
        let result = await PassportPipeline().run(image, spec: try Self.spec())

        #expect(result.output == nil, "a two-person photo produced a passport photo")
        #expect(result.failures.contains { $0.id == .faceCount }
                || result.failureReason != nil,
                "failed for \(result.failures.map(\.id.rawValue))")
    }

    @Test("a heavily blurred portrait is rejected for sharpness")
    func blurred() async throws {
        let source = try ImageLoader.load(contentsOf: #require(RepoPaths.fixtures)
            .appendingPathComponent("photos/IMG_0012.HEIC"))
        let pixels = try #require(ImageConversion.pixelImage(from: source))
        let blurred = Self.boxBlur(pixels, radius: 12)
        let image = try #require(ImageConversion.cgImage(from: blurred))

        let result = await PassportPipeline().run(image, spec: try Self.spec())
        #expect(result.output == nil, "a blurred photo was accepted")

        let failedIDs: [CheckID] = result.failures.map(\.id)
        if !failedIDs.isEmpty {
            let blamesQuality = failedIDs.contains(.sharpness) || failedIDs.contains(.resolution)
            #expect(blamesQuality, "failed for \(failedIDs) instead of sharpness")
        }
    }

    /// A separable box blur, repeated, which is enough to destroy fine detail.
    static func boxBlur(_ image: PixelImage, radius: Int) -> PixelImage {
        var current = image
        for _ in 0..<3 {
            var horizontal = current
            for y in 0..<current.height {
                for x in 0..<current.width {
                    var sums = [Int](repeating: 0, count: 3)
                    var count = 0
                    for dx in -radius...radius {
                        let (cx, cy) = current.clamped(x: x + dx, y: y)
                        let p = current.offset(x: cx, y: cy)
                        for c in 0..<3 { sums[c] += Int(current.pixels[p + c]) }
                        count += 1
                    }
                    let p = current.offset(x: x, y: y)
                    for c in 0..<3 { horizontal.pixels[p + c] = UInt8(sums[c] / count) }
                }
            }
            var vertical = horizontal
            for y in 0..<current.height {
                for x in 0..<current.width {
                    var sums = [Int](repeating: 0, count: 3)
                    var count = 0
                    for dy in -radius...radius {
                        let (cx, cy) = current.clamped(x: x, y: y + dy)
                        let p = horizontal.offset(x: cx, y: cy)
                        for c in 0..<3 { sums[c] += Int(horizontal.pixels[p + c]) }
                        count += 1
                    }
                    let p = current.offset(x: x, y: y)
                    for c in 0..<3 { vertical.pixels[p + c] = UInt8(sums[c] / count) }
                }
            }
            current = vertical
        }
        return current
    }
}
