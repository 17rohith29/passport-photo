import CoreGraphics
import Foundation
import SpecKit
import Testing
import TestSupport
@testable import PhotoAnalysis
@testable import PhotoPipeline

/// Canada, the US, the UK and Australia all rule out an edited photo outright. Replacing the
/// background is an edit, so for those documents the app crops, levels and scales but leaves the
/// user's own wall alone — and then the wall has to satisfy the spec on its own merits.
@Suite("Keep the user's background", .serialized, .enabled(if: RepoPaths.hasFixturePhotos))
struct KeepBackgroundTests {

    static func spec(_ id: String) throws -> DocumentSpec {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("specs")
        return try SpecLoader.load(contentsOf: dir.appendingPathComponent("\(id).json"))
    }

    static func source() throws -> CGImage {
        let url = try #require(RepoPaths.fixtures).appendingPathComponent("photos/IMG_0012.HEIC")
        return try ImageLoader.load(data: try Data(contentsOf: url))
    }

    @Test("the documents that forbid editing are marked, and the rest are not")
    func editingPolicyMatchesTheAuthority() throws {
        // Each of these asserts it in its own editingRisk text: Canada "rules out editing
        // software", the US "requires an unedited photo", GOV.UK "requires a photo unaltered by
        // computer software", Australia "does not accept retouched photos".
        for id in ["ca-passport", "us-passport", "gb-passport", "au-passport"] {
            #expect(try Self.spec(id).forbidsEditing, "\(id) should be marked forbidden")
        }
        // These state a background preference, not a prohibition on editing.
        for id in ["in-passport", "cn-visa", "eu-schengen-visa", "ru-visa"] {
            #expect(try !Self.spec(id).forbidsEditing, "\(id)")
        }
    }

    /// Replace stays the default even where editing is forbidden. Measured on real photos, an
    /// actual wall reads 173-211 on its darkest channel where these specs demand 245 or more, so
    /// defaulting to `keep` would reject almost everyone. It is offered explicitly instead.
    @Test("replace is the default everywhere, for a measured reason")
    func replaceIsTheDefault() throws {
        for id in ["ca-passport", "us-passport", "gb-passport", "au-passport",
                   "in-passport", "cn-visa", "eu-schengen-visa", "ru-visa"] {
            #expect(BackgroundMode.default(for: try Self.spec(id)) == .replace, "\(id)")
        }
    }

    /// Keeping the wall must say what is actually wrong. The old message came from the cut-out
    /// integrity signal and blamed separation, which does not happen in this mode at all.
    @Test("a wall that is too dark is reported as a wall problem, not a separation problem")
    func wallFailureSaysSo() async throws {
        let spec = try Self.spec("us-passport")
        let result = await PassportPipeline().run(try Self.source(), spec: spec, mode: .keep)
        let background = try #require(result.allChecks.first { $0.id == .background })
        #expect(background.measured.contains("your own wall"))
        if background.status == .fail {
            let message = try #require(background.userMessage)
            #expect(message.contains("wall behind you"))
            #expect(!message.contains("separate you"))
            #expect(background.fixability == .retakeRequired)
        }
    }

    /// The point of the mode: the wall in the output must be the user's own wall, not ours.
    @Test("keeping the background leaves the real wall in the photo")
    func wallIsTheUsersOwn() async throws {
        let spec = try Self.spec("ca-passport")
        let image = try Self.source()
        let pipeline = PassportPipeline()

        let kept = await pipeline.run(image, spec: spec, mode: .keep)
        let replaced = await pipeline.run(image, spec: spec, mode: .replace)

        let keptOut = try #require(kept.output?.digital)
        let replacedOut = try #require(replaced.output?.digital)
        let keptPixels = try #require(ImageConversion.pixelImage(from: keptOut))
        let replacedPixels = try #require(ImageConversion.pixelImage(from: replacedOut))

        let target = try #require(RGB(hex: spec.background?.colorHex ?? "#FFFFFF"))
        let (tr, tg, tb) = target.bytes

        func cornerIsExactly(_ image: PixelImage, _ r: UInt8, _ g: UInt8, _ b: UInt8) -> Bool {
            let p = image.offset(x: 4, y: 4)
            return image.pixels[p] == r && image.pixels[p + 1] == g && image.pixels[p + 2] == b
        }
        // Replacing paints the spec colour exactly; keeping cannot, because a real wall is never
        // one exact value.
        #expect(cornerIsExactly(replacedPixels, tr, tg, tb))
        #expect(!cornerIsExactly(keptPixels, tr, tg, tb), "kept output still has a painted corner")
        #expect(kept.isUnedited)
        #expect(!replaced.isUnedited)
    }

    /// The background check is what makes the mode honest: the user's wall is now judged, not
    /// papered over.
    @Test("the user's own wall is judged against the spec")
    func wallIsStillChecked() async throws {
        let spec = try Self.spec("ca-passport")
        let result = await PassportPipeline().run(try Self.source(), spec: spec, mode: .keep)
        let background = try #require(
            result.allChecks.first { $0.id == .background }, "no background check ran"
        )
        #expect(!background.measured.isEmpty)
    }

    @Test("keeping the background still produces the exact required pixel size")
    func sizeIsUnaffected() async throws {
        for id in ["ca-passport", "gb-passport"] {
            let spec = try Self.spec(id)
            let result = await PassportPipeline().run(try Self.source(), spec: spec, mode: .keep)
            guard let out = result.output?.digital else { continue }
            let expected = try #require(spec.photo.digital.outputSizePx)
            #expect(out.width == Int(expected.width), "\(id)")
            #expect(out.height == Int(expected.height), "\(id)")
        }
    }

    /// Cropping and scaling are not what those authorities forbid — compositing is. Nothing in
    /// the kept output may be the painted spec colour.
    @Test("nothing in a kept photo is painted with our colour")
    func noPaintedPixels() async throws {
        let spec = try Self.spec("us-passport")
        let result = await PassportPipeline().run(try Self.source(), spec: spec, mode: .keep)
        let out = try #require(result.output?.digital)
        let pixels = try #require(ImageConversion.pixelImage(from: out))
        let target = try #require(RGB(hex: spec.background?.colorHex ?? "#FFFFFF"))
        let (tr, tg, tb) = target.bytes

        var painted = 0
        for i in 0..<(pixels.width * pixels.height) {
            let p = i * 4
            if pixels.pixels[p] == tr && pixels.pixels[p + 1] == tg && pixels.pixels[p + 2] == tb {
                painted += 1
            }
        }
        // A real photograph will land on the exact value by chance here and there; a composited
        // one is mostly that value.
        let fraction = Double(painted) / Double(pixels.width * pixels.height)
        #expect(fraction < 0.02, "\(fraction * 100)% of the kept photo is our exact colour")
    }
}
