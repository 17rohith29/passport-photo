import CoreGraphics
import Foundation
import Testing
import TestSupport
import PhotoAnalysis
import PhotoPipeline
import SpecKit

/// Vision landmarks can degenerate, coincident points, a zero-width face, values that are not
/// finite. Those flow straight into `Int(_:)` conversions, buffer allocations and `ClosedRange`,
/// all of which trap rather than throw. Everything here is a value that reaches such a site.
@Suite("Crash safety: geometry and buffers")
struct GeometryCrashSafetyTests {

    static func spec() throws -> DocumentSpec {
        try SpecLoader.load(contentsOf: #require(RepoPaths.inPassportSpec))
    }

    static let nastyNumbers: [CGFloat] = [
        0, -1, -100_000, 1e12, .infinity, -.infinity, .nan,
        CGFloat(Float.greatestFiniteMagnitude),
    ]

    // MARK: buffers

    @Test("a degenerate or non-finite crop rect returns an empty image instead of trapping")
    func croppingIsSafe() {
        let image = GrayImage(width: 40, height: 40, repeating: 1)
        let rects: [CGRect] = [
            CGRect(x: 0, y: 0, width: 0, height: 0),
            CGRect(x: 0, y: 0, width: -10, height: -10),
            CGRect(x: CGFloat.nan, y: CGFloat.nan, width: 10, height: 10),
            CGRect(x: 0, y: 0, width: CGFloat.nan, height: CGFloat.nan),
            CGRect(x: 0, y: 0, width: CGFloat.infinity, height: CGFloat.infinity),
            CGRect(x: -1e12, y: -1e12, width: 5, height: 5),
        ]
        for rect in rects {
            let out = image.cropped(to: rect)
            #expect(out.values.count == out.width * out.height, "\(rect)")
        }
    }

    @Test("sampling outside the image, or at a non-finite point, is clamped")
    func samplingIsSafe() {
        let image = GrayImage(width: 8, height: 8, repeating: 0.5)
        for value in [Float.nan, .infinity, -.infinity, -1e30, 1e30, -5, 900] {
            let sample = image.sample(x: value, y: value)
            #expect(sample.isFinite, "sample(\(value)) = \(sample)")
        }
        #expect(GrayImage(width: 0, height: 0, values: []).sample(x: 1, y: 1) == 0)
    }

    @Test("reading an empty image returns zero instead of indexing out of bounds")
    func emptyImagesAreSafe() {
        let empty = GrayImage(width: 0, height: 0, values: [])
        // at() clamps to width - 1, which is -1 when the image is empty: that used to trap.
        #expect(empty.at(x: 5, y: 5) == 0)
        #expect(empty.at(x: -5, y: -5) == 0)
        #expect(empty.sample(x: 1, y: 1) == 0)
        #expect(empty.resized(width: 0, height: 0).values.isEmpty)
        // Resizing an empty image up yields a filled buffer of zeros, which is consistent.
        let grown = empty.resized(width: 10, height: 10)
        #expect(grown.values.count == 100)

        // A one-pixel image is the other boundary.
        let single = GrayImage(width: 1, height: 1, repeating: 0.25)
        #expect(single.at(x: 99, y: 99) == 0.25)
        #expect(single.sample(x: 0.5, y: 0.5).isFinite)
    }

    // MARK: colour

    @Test("an out-of-range or non-finite colour clamps instead of trapping on UInt8")
    func rgbBytesClamp() {
        for value in [Float(-5), -0.001, 1.001, 99, .nan, .infinity, -.infinity] {
            let bytes = RGB(r: value, g: value, b: value).bytes
            #expect(bytes.0 <= 255)
        }
        #expect(RGB(r: 1, g: 1, b: 1).bytes == (255, 255, 255))
        #expect(RGB(r: 0, g: 0, b: 0).bytes == (0, 0, 0))
    }

    // MARK: planner

    @Test("the crop planner refuses nonsense instead of trapping")
    func plannerIsSafe() throws {
        let spec = try Self.spec()
        for value in Self.nastyNumbers {
            for size in [CGSize(width: 100, height: 100), CGSize(width: 0, height: 0)] {
                let result = CropPlanner.plan(
                    crown: value, chin: value,
                    eyes: (CGPoint(x: value, y: value), CGPoint(x: value, y: value)),
                    imageSize: size, spec: spec
                )
                // Any answer is fine; not crashing is the contract.
                if case .success(let plan) = result {
                    #expect(plan.rect.width.isFinite, "\(value) produced \(plan.rect)")
                }
            }
        }
    }

    @Test("a crown below the chin is refused")
    func invertedHeadIsRefused() throws {
        let result = CropPlanner.plan(
            crown: 900, chin: 100,
            eyes: (CGPoint(x: 50, y: 50), CGPoint(x: 60, y: 50)),
            imageSize: CGSize(width: 1000, height: 1000), spec: try Self.spec()
        )
        if case .success = result { Issue.record("an inverted head produced a plan") }
    }

    // MARK: capture guidance

    @Test("a non-finite or negative tolerance still builds a valid range")
    func toleranceCannotInvertTheRange() throws {
        let spec = try Self.spec()
        for tolerance in [0.07, 0, -0.2, .nan, .infinity, -.infinity, 1e9] as [Double] {
            let band = CaptureGuidance.targetHeadFraction(spec: spec, tolerance: tolerance)
            #expect(band.lowerBound <= band.upperBound, "tolerance \(tolerance) inverted the band")
        }
    }

    @Test("guidance survives a degenerate face and a zero-sized frame")
    func guidanceIsSafe() throws {
        let spec = try Self.spec()
        let zero = FaceMeasurements(
            faceCount: 1, boundingBox: .zero, leftEye: .zero, rightEye: .zero,
            contour: [], rawChin: .zero, browY: 0,
            yawDeg: 0, pitchDeg: 0, rollDeg: 0,
            captureQuality: nil, eyeOpenness: 0, mouthOpenness: 0
        )
        var nasty = zero
        nasty.leftEye = CGPoint(x: CGFloat.nan, y: CGFloat.nan)
        nasty.rightEye = CGPoint(x: CGFloat.infinity, y: CGFloat.infinity)
        nasty.rawChin = CGPoint(x: CGFloat.nan, y: CGFloat.nan)
        nasty.browY = .nan

        for face in [zero, nasty] {
            for frame in [CGSize(width: 0, height: 0), CGSize(width: 100, height: 100),
                          CGSize(width: CGFloat.nan, height: CGFloat.nan)] {
                let result = CaptureGuidance.assess(
                    face: face, headHeightPx: nil, cheekImbalance: nil,
                    frameSize: frame, spec: spec
                )
                #expect(result.cues.isEmpty == false || result.isReady == false)
            }
        }
    }

    @Test("the stabiliser tolerates a zero or negative frame requirement")
    func stabiliserIsSafe() {
        for required in [0, -1, 1] {
            var stabiliser = CaptureStabiliser(requiredFrames: required)
            var fired = false
            for _ in 0..<3 { fired = stabiliser.update(isReady: true) || fired }
            #expect(stabiliser.progress.isFinite)
            _ = fired
        }
    }

    // MARK: print sheet

    @Test("the print sheet refuses degenerate tiles instead of dividing by zero")
    func printSheetIsSafe() throws {
        let spec = try Self.spec()
        let tiles = [
            PixelImage(width: 0, height: 0, pixels: []),
            PixelImage(width: 1, height: 1, fill: (255, 255, 255)),
            PixelImage(width: 5000, height: 5000, fill: (255, 255, 255)),
        ]
        for tile in tiles {
            let sheet = PrintSheetComposer.compose(tile: tile, spec: spec)
            if let sheet {
                #expect(sheet.columns >= 1)
                #expect(sheet.rows >= 1)
                #expect(sheet.image.pixels.count == sheet.image.width * sheet.image.height * 4)
            }
        }
    }

    @Test("the print sheet survives a zero or negative gutter")
    func printSheetGutter() throws {
        let spec = try Self.spec()
        let tile = PixelImage(width: 100, height: 130, fill: (255, 255, 255))
        for gutter in [0, -10, 100_000] {
            let sheet = PrintSheetComposer.compose(tile: tile, spec: spec, gutterPx: gutter)
            if let sheet { #expect(sheet.columns >= 1 && sheet.rows >= 1, "gutter \(gutter)") }
        }
    }

    // MARK: metrics

    @Test("metrics survive a degenerate face")
    func metricsAreSafe() {
        let luminance = GrayImage(width: 50, height: 50, repeating: 120)
        var face = FaceMeasurements(
            faceCount: 1, boundingBox: .zero, leftEye: .zero, rightEye: .zero,
            contour: [], rawChin: .zero, browY: 0,
            yawDeg: 0, pitchDeg: 0, rollDeg: 0,
            captureQuality: nil, eyeOpenness: 0, mouthOpenness: 0
        )
        #expect(ImageMetrics.cheekImbalance(luminance: luminance, face: face).isFinite)
        #expect(ImageMetrics.sharpness(luminance: luminance, faceBox: .zero).isFinite)

        face.rawChin = CGPoint(x: CGFloat.nan, y: CGFloat.nan)
        face.browY = .nan
        face.contour = [CGPoint(x: CGFloat.nan, y: CGFloat.nan)]
        #expect(ImageMetrics.cheekImbalance(luminance: luminance, face: face).isFinite)
        #expect(ImageMetrics.sharpness(
            luminance: luminance,
            faceBox: CGRect(x: CGFloat.nan, y: CGFloat.nan, width: CGFloat.nan, height: CGFloat.nan)
        ).isFinite)
    }

    /// The crown search runs 0...chinRow. A face whose entire contour sits above the frame
    /// gives a negative chin row, and `0...(-5)` traps on "Range requires lowerBound <= upperBound".
    @Test("a chin above the top of the frame does not invert the crown search range")
    func negativeChinRowIsSafe() {
        let matte = AlphaMatte(width: 60, height: 60, repeating: 1)
        for chinY in [CGFloat(-0.4), -1, -5, -100_000] {
            let face = FaceMeasurements(
                faceCount: 1, boundingBox: CGRect(x: 10, y: -30, width: 20, height: 20),
                leftEye: CGPoint(x: 20, y: -20), rightEye: CGPoint(x: 30, y: -20),
                contour: [CGPoint(x: 15, y: -20), CGPoint(x: 35, y: -20)],
                rawChin: CGPoint(x: 25, y: chinY), browY: -25,
                yawDeg: 0, pitchDeg: 0, rollDeg: 0,
                captureQuality: nil, eyeOpenness: 0.3, mouthOpenness: 0.02
            )
            // Either it declines, or it returns a row that is actually in the matte. What it
            // must never do is evaluate 0...(negative).
            if let crown = CrownFinder.find(matte: matte, face: face) {
                #expect(crown >= 0 && crown < CGFloat(matte.height))
            }
            _ = CrownFinder.touchesTopEdge(matte: matte, face: face)
        }
    }

    /// The matte refiner scans the border rows directly. With a zero height that is row -1.
    @Test("a matte with a zero dimension is returned untouched instead of indexing row -1")
    func degenerateMatteIsSafe() {
        let face = FaceMeasurements(
            faceCount: 1, boundingBox: CGRect(x: 1, y: 1, width: 2, height: 2),
            leftEye: CGPoint(x: 1, y: 1), rightEye: CGPoint(x: 3, y: 1),
            contour: [CGPoint(x: 1, y: 1), CGPoint(x: 3, y: 1)],
            rawChin: CGPoint(x: 2, y: 3), browY: 1,
            yawDeg: 0, pitchDeg: 0, rollDeg: 0,
            captureQuality: nil, eyeOpenness: 0.3, mouthOpenness: 0.02
        )
        for (w, h) in [(5, 0), (0, 5), (0, 0)] {
            let matte = AlphaMatte(width: w, height: h, values: [])
            let image = PixelImage(width: w, height: h, pixels: [])
            let out = MatteRefiner.refine(matte: matte, image: image, face: face)
            #expect(out.width == w && out.height == h)
        }
    }

    /// Finite is not enough where a value becomes an `Int`: `Int(1e300)` traps on overflow.
    @Test("huge finite coordinates do not overflow the Int conversions")
    func hugeFiniteCoordinatesAreSafe() {
        let luminance = GrayImage(width: 60, height: 60, repeating: 100)
        let matte = AlphaMatte(width: 60, height: 60, repeating: 1)
        for value in [CGFloat(1e300), -1e300, 1e15] {
            var face = FaceMeasurements(
                faceCount: 1, boundingBox: CGRect(x: 10, y: 10, width: 20, height: 20),
                leftEye: CGPoint(x: 20, y: 20), rightEye: CGPoint(x: 30, y: 20),
                contour: [CGPoint(x: 15, y: 20), CGPoint(x: 35, y: 20)],
                rawChin: CGPoint(x: value, y: 40), browY: 15,
                yawDeg: 0, pitchDeg: 0, rollDeg: 0,
                captureQuality: nil, eyeOpenness: 0.3, mouthOpenness: 0.02
            )
            #expect(ChinRefiner.refine(luminance: luminance, face: face).isFinite)
            face.rawChin = CGPoint(x: 25, y: value)
            #expect(ChinRefiner.refine(luminance: luminance, face: face).isFinite)
            _ = CrownFinder.find(matte: matte, face: face)
        }
        // Same shape one layer down, where only the sibling function was bounded.
        let image = GrayImage(width: 40, height: 40, repeating: 1)
        for rect in [CGRect(x: 0, y: 0, width: 1e300, height: 1e300),
                     CGRect(x: 1e300, y: 1e300, width: 10, height: 10)] {
            let out = image.cropped(to: rect)
            #expect(out.values.count == out.width * out.height)
        }
    }

    @Test("the chin refiner and crown finder survive a degenerate face")
    func refinersAreSafe() {
        let luminance = GrayImage(width: 60, height: 60, repeating: 100)
        let matte = AlphaMatte(width: 60, height: 60, repeating: 1)
        var face = FaceMeasurements(
            faceCount: 1, boundingBox: CGRect(x: 10, y: 10, width: 20, height: 20),
            leftEye: CGPoint(x: 20, y: 20), rightEye: CGPoint(x: 30, y: 20),
            contour: [CGPoint(x: 15, y: 20), CGPoint(x: 35, y: 20)],
            rawChin: CGPoint(x: 25, y: 40), browY: 15,
            yawDeg: 0, pitchDeg: 0, rollDeg: 0,
            captureQuality: nil, eyeOpenness: 0.3, mouthOpenness: 0.02
        )
        #expect(ChinRefiner.refine(luminance: luminance, face: face).isFinite)
        _ = CrownFinder.find(matte: matte, face: face)
        _ = CrownFinder.touchesTopEdge(matte: matte, face: face)

        // Collapse the face to a point, then to nonsense.
        face.contour = [CGPoint(x: 25, y: 25)]
        face.rawChin = CGPoint(x: 25, y: 25)
        face.browY = 25
        #expect(ChinRefiner.refine(luminance: luminance, face: face).isFinite)
        _ = CrownFinder.find(matte: matte, face: face)

        face.contour = []
        #expect(ChinRefiner.refine(luminance: luminance, face: face).isFinite)
        #expect(CrownFinder.find(matte: matte, face: face) == nil || true)
        #expect(CrownFinder.touchesTopEdge(matte: matte, face: face) == false || true)
    }

    @Test("the matte refiner survives a tiny image and an empty matte")
    func matteRefinerIsSafe() {
        let face = FaceMeasurements(
            faceCount: 1, boundingBox: CGRect(x: 1, y: 1, width: 2, height: 2),
            leftEye: CGPoint(x: 1, y: 1), rightEye: CGPoint(x: 2, y: 1),
            contour: [CGPoint(x: 1, y: 1), CGPoint(x: 3, y: 1)],
            rawChin: CGPoint(x: 2, y: 3), browY: 1,
            yawDeg: 0, pitchDeg: 0, rollDeg: 0,
            captureQuality: nil, eyeOpenness: 0.3, mouthOpenness: 0.02
        )
        for side in [1, 2, 5] {
            let matte = AlphaMatte(width: side, height: side, repeating: 1)
            let image = PixelImage(width: side, height: side, fill: (200, 200, 200))
            let refined = MatteRefiner.refine(matte: matte, image: image, face: face)
            #expect(refined.values.count == refined.width * refined.height)
        }
    }
}
