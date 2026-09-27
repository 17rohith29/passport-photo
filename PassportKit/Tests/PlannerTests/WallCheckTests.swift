import CoreGraphics
import Foundation
import SpecKit
import Testing
import TestSupport
@testable import PhotoAnalysis
@testable import PhotoPipeline

/// The keep-mode wall check used to be a tautology: it took the darkest pixel of a region that
/// only admitted pixels already above the threshold, then checked it against that threshold.
/// A 180-grey wall with one bright corner passed, reporting "100% brightness".
@Suite("Keep-mode wall check")
struct WallCheckTests {

    static func spec() throws -> DocumentSpec {
        try SpecLoader.load(contentsOf: #require(RepoPaths.inPassportSpec))
    }

    static func checker() -> ComplianceChecker {
        ComplianceChecker(analyzer: VisionFaceAnalyzer(), segmenter: VisionSubjectSegmenter())
    }

    /// A wall of one tone, optionally with a small bright patch in a top corner.
    static func wall(_ tone: UInt8, brightPatch: Int = 0) -> PixelImage {
        var image = PixelImage(width: 600, height: 800, fill: (tone, tone, tone))
        for y in 0..<brightPatch {
            for x in 0..<brightPatch {
                let p = image.offset(x: x, y: y)
                image.pixels[p] = 255; image.pixels[p + 1] = 255; image.pixels[p + 2] = 255
            }
        }
        return image
    }

    @Test("a dark wall fails, and a bright speck in the corner cannot rescue it")
    func brightSpeckCannotRescueADarkWall() throws {
        let spec = try Self.spec()
        let background = try #require(RGB(hex: spec.background?.colorHex ?? "#FFFFFF"))
        for patch in [0, 12, 40] {
            let checks = Self.checker().backgroundChecks(
                Self.wall(180, brightPatch: patch), spec: spec,
                background: background, mode: .keep
            )
            let check = try #require(checks.first)
            #expect(
                check.status == .fail,
                "a 180 wall with a \(patch)px bright corner passed: \(check.measured)"
            )
            // And it must not report a brightness the wall does not have.
            #expect(!check.measured.contains("100%"), "\(check.measured)")
        }
    }

    @Test("a genuinely white wall passes")
    func whiteWallPasses() throws {
        let spec = try Self.spec()
        let background = try #require(RGB(hex: spec.background?.colorHex ?? "#FFFFFF"))
        let check = try #require(Self.checker().backgroundChecks(
            Self.wall(252), spec: spec, background: background, mode: .keep
        ).first)
        #expect(check.status == .pass, "\(check.measured)")
    }

    /// The reported number has to describe the wall, not the brightest thing in the frame.
    @Test("the reported brightness tracks the wall's real tone")
    func reportedBrightnessIsHonest() throws {
        let spec = try Self.spec()
        let background = try #require(RGB(hex: spec.background?.colorHex ?? "#FFFFFF"))
        let checker = Self.checker()
        for tone in [UInt8(120), 180, 210] {
            let check = try #require(checker.backgroundChecks(
                Self.wall(tone, brightPatch: 20), spec: spec,
                background: background, mode: .keep
            ).first)
            let expected = Int((Double(tone) / 255 * 100).rounded())
            #expect(
                check.measured.contains("\(expected)%"),
                "wall \(tone) should read \(expected)%, said: \(check.measured)"
            )
        }
    }

    /// The same tautology lived on the DEFAULT path. Measured before the fix: a pure black
    /// photo with a 40x40 white corner and two white side strips passed, reporting "darkest
    /// channel 255", for every wall tone from 0 to 244.
    @Test("a fake backdrop pieced out of a corner patch cannot pass in replace mode")
    func fakeBackdropFailsInReplaceMode() throws {
        let spec = try Self.spec()
        let background = try #require(RGB(hex: spec.background?.colorHex ?? "#FFFFFF"))
        let checker = Self.checker()

        for wall in [UInt8(0), 60, 120, 180, 244] {
            var image = PixelImage(width: 630, height: 810, fill: (wall, wall, wall))
            func paintWhite(_ xs: Swift.Range<Int>, _ ys: Swift.Range<Int>) {
                for y in ys {
                    for x in xs {
                        let p = image.offset(x: x, y: y)
                        image.pixels[p] = 255; image.pixels[p + 1] = 255; image.pixels[p + 2] = 255
                    }
                }
            }
            paintWhite(0..<40, 0..<40)          // the corner the region is seeded from
            paintWhite(0..<45, 202..<444)       // side strips, to satisfy sideMarginPurity
            paintWhite(585..<630, 202..<444)

            let check = try #require(checker.backgroundChecks(
                image, spec: spec, background: background, mode: .replace
            ).first)
            #expect(
                check.status == .fail,
                "wall \(wall) passed on a 4.6% fake backdrop: \(check.measured)"
            )
        }
    }

    /// LESSONS 20's photo: a slab of the original room with a painted border around it. The
    /// border covers the side strips sideMarginPurity samples, so that fix alone is evaded.
    @Test("a slab of the original room behind a painted border cannot pass")
    func paintedBorderAroundASlabFails() throws {
        let spec = try Self.spec()
        let background = try #require(RGB(hex: spec.background?.colorHex ?? "#FFFFFF"))
        var image = PixelImage(width: 630, height: 810, fill: (255, 255, 255))
        // A 60 px white border, dark room inside.
        for y in 60..<750 {
            for x in 60..<570 {
                let p = image.offset(x: x, y: y)
                image.pixels[p] = 60; image.pixels[p + 1] = 60; image.pixels[p + 2] = 60
            }
        }
        let check = try #require(Self.checker().backgroundChecks(
            image, spec: spec, background: background, mode: .replace
        ).first)
        #expect(check.status == .fail, "a bordered slab passed: \(check.measured)")
    }

    /// The floor has to leave room for real photos: measured 40-60% backdrop across three specs
    /// and the fixture set, India's 80%-of-height head being the tightest at 40%.
    @Test("a normally framed photo still passes")
    func realisticCoveragePasses() throws {
        let spec = try Self.spec()
        let background = try #require(RGB(hex: spec.background?.colorHex ?? "#FFFFFF"))
        var image = PixelImage(width: 630, height: 810, fill: (255, 255, 255))
        // A subject blob covering ~58% of the frame, leaving ~42% backdrop.
        for y in 170..<810 {
            for x in 150..<480 {
                let p = image.offset(x: x, y: y)
                image.pixels[p] = 120; image.pixels[p + 1] = 90; image.pixels[p + 2] = 70
            }
        }
        let check = try #require(Self.checker().backgroundChecks(
            image, spec: spec, background: background, mode: .replace
        ).first)
        #expect(check.status == .pass, "\(check.measured)")
    }

    @Test("wallBrightness is the median, so a minority of bright pixels cannot carry it")
    func medianNotExtreme() {
        let checker = Self.checker()
        #expect(checker.wallBrightness(Self.wall(180)) == 180)
        #expect(checker.wallBrightness(Self.wall(180, brightPatch: 100)) == 180)
    }

    /// The renderer is the one geometry entry point that had no hostile-input coverage.
    @Test("the renderer refuses a degenerate crop plan instead of trapping")
    func rendererIsSafe() {
        let source = PixelImage(width: 80, height: 100, fill: (200, 200, 200))
        let matte = AlphaMatte(width: 80, height: 100, repeating: 1)
        let nasty: [CGRect] = [
            CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10),
            CGRect(x: 1e300, y: 1e300, width: 10, height: 10),
            CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 10),
            CGRect(x: 0, y: 0, width: -5, height: 10),
            CGRect(x: 0, y: 0, width: 0, height: 0),
        ]
        for rect in nasty {
            let plan = CropPlan(rect: rect, outputSize: CGSize(width: 40, height: 50), scale: 1)
            _ = Renderer.render(
                source: source, matte: matte, plan: plan, background: .white, sharpen: []
            )
        }
        for size in [CGSize(width: CGFloat.nan, height: 50), CGSize(width: 1e30, height: 1e30),
                     CGSize(width: 0, height: 50)] {
            let plan = CropPlan(
                rect: CGRect(x: 0, y: 0, width: 40, height: 50), outputSize: size, scale: 1
            )
            #expect(Renderer.render(
                source: source, matte: matte, plan: plan, background: .white, sharpen: []
            ) == nil)
        }
    }
}
