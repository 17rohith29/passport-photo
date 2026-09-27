import CoreGraphics
import Foundation
import SpecKit
import Testing
import TestSupport
@testable import PhotoAnalysis
@testable import PhotoPipeline

/// Audits the checks added while fixing LESSONS 39/41/42, with the scepticism those lessons
/// describe. `minBackdropCoverage` was calibrated on four photos of one person against one wall,
/// so the risk is not only that a check cannot fail, it is that it rejects real people.
@Suite("Audit of the new checks")
struct NewCheckAuditTests {

    static func specs() throws -> [DocumentSpec] {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("specs")
        return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.contains("schema") }
            .map { try SpecLoader.load(contentsOf: $0) }
            .filter { $0.status.isTestFixture != true }
            .sorted { $0.id < $1.id }
    }

    static func checker() -> ComplianceChecker {
        ComplianceChecker(analyzer: VisionFaceAnalyzer(), segmenter: VisionSubjectSegmenter())
    }

    /// A composited photo: spec-coloured backdrop, an elliptical head and a shoulder mass that
    /// runs off the bottom, as every real passport crop does.
    /// `headScale` widens the head; `hair` adds volume around it.
    static func composite(
        width: Int, height: Int, background: RGB,
        headScale: Double = 1.0, hair: Double = 0.0, shoulderScale: Double = 1.0
    ) -> PixelImage {
        let (br, bg, bb) = background.bytes
        var image = PixelImage(width: width, height: height, fill: (br, bg, bb))

        let headHeight = Double(height) * 0.62
        let headWidth = headHeight * 0.72 * headScale
        let cx = Double(width) / 2
        let cy = Double(height) * 0.40
        let rx = headWidth / 2 * (1 + hair)
        let ry = headHeight / 2 * (1 + hair * 0.5)

        let shoulderTop = cy + ry * 0.85
        let shoulderHalf = headWidth * 1.35 * shoulderScale

        for y in 0..<height {
            for x in 0..<width {
                let dx = (Double(x) - cx) / rx
                let dy = (Double(y) - cy) / ry
                let inHead = dx * dx + dy * dy <= 1
                let inShoulders = Double(y) >= shoulderTop
                    && abs(Double(x) - cx) <= shoulderHalf
                guard inHead || inShoulders else { continue }
                let p = image.offset(x: x, y: y)
                image.pixels[p] = 90; image.pixels[p + 1] = 70; image.pixels[p + 2] = 60
            }
        }
        return image
    }

    static func coverage(_ image: PixelImage, spec: DocumentSpec) -> Double {
        let minimum = UInt8(spec.background?.minChannelValue ?? 245)
        let region = Self.checker().backdropRegion(image, minimum: minimum)
        return Double(region.filter { $0 }.count) / Double(image.width * image.height)
    }

    /// The over-strictness question: does a bigger head, a wider face, big hair or broad
    /// shoulders push a legitimate photo under the 30% floor?
    @Test("a large head, big hair and broad shoulders still clear the coverage floor")
    func realisticVariationStillPasses() throws {
        for spec in try Self.specs() {
            let px = try #require(spec.photo.digital.outputSizePx)
            let background = try #require(RGB(hex: spec.background?.colorHex ?? "#FFFFFF"))
            for (label, head, hair, shoulders) in [
                ("nominal", 1.0, 0.0, 1.0),
                ("wide face", 1.18, 0.0, 1.0),
                ("big hair", 1.0, 0.18, 1.0),
                ("broad shoulders", 1.0, 0.0, 1.25),
                ("all three", 1.15, 0.15, 1.2),
            ] {
                let image = Self.composite(
                    width: Int(px.width), height: Int(px.height), background: background,
                    headScale: head, hair: hair, shoulderScale: shoulders
                )
                let checks = Self.checker().backgroundChecks(
                    image, spec: spec, background: background, mode: .replace
                )
                let check = try #require(checks.first)
                let cover = Self.coverage(image, spec: spec)
                #expect(
                    check.status == .pass,
                    "\(spec.id) \(label): coverage \(cover * 100)%, \(check.measured)"
                )
                // Margin, not just a pass: at 0.30 a China visa with ordinary hair measured
                // 29.5% and failed. If a future change narrows this, the floor moved without
                // re-measuring what a real person looks like.
                #expect(
                    cover - Tuning.default.minBackdropCoverage > 0.08,
                    "\(spec.id) \(label) leaves only \(cover - Tuning.default.minBackdropCoverage) of margin"
                )
            }
        }
    }

    /// And the tautology question: each new signal must be able to fail on its own.
    @Test("each new background signal can actually fail")
    func eachSignalCanFail() throws {
        let spec = try #require(try Self.specs().first { $0.id == "in-passport" })
        let background = try #require(RGB(hex: spec.background?.colorHex ?? "#FFFFFF"))
        let px = try #require(spec.photo.digital.outputSizePx)
        let w = Int(px.width), h = Int(px.height)
        let checker = Self.checker()

        // Coverage: a subject that swallows the frame.
        let swallowed = Self.composite(
            width: w, height: h, background: background,
            headScale: 2.2, hair: 0.5, shoulderScale: 2.5
        )
        #expect(
            checker.backgroundChecks(
                swallowed, spec: spec, background: background, mode: .replace
            ).first?.status == .fail,
            "coverage never fails: \(Self.coverage(swallowed, spec: spec) * 100)%"
        )

        // Top band: a dark room above the head.
        var darkTop = Self.composite(width: w, height: h, background: background)
        for y in 0..<(h / 6) {
            for x in 0..<w {
                let p = darkTop.offset(x: x, y: y)
                darkTop.pixels[p] = 40; darkTop.pixels[p + 1] = 40; darkTop.pixels[p + 2] = 40
            }
        }
        #expect(
            checker.backgroundChecks(
                darkTop, spec: spec, background: background, mode: .replace
            ).first?.status == .fail,
            "top band never fails"
        )

        // Subject reaching the bottom: a floating blob that touches no edge.
        var floating = PixelImage(width: w, height: h, fill: background.bytes)
        for y in (h / 5)..<(h * 3 / 5) {
            for x in (w / 5)..<(w * 4 / 5) {
                let p = floating.offset(x: x, y: y)
                floating.pixels[p] = 90; floating.pixels[p + 1] = 70; floating.pixels[p + 2] = 60
            }
        }
        #expect(
            !checker.subjectReachesBottom(
                floating, backdrop: checker.backdropRegion(floating, minimum: 245)
            ),
            "subjectReachesBottom never fails"
        )
        // …and passes for a normal composite.
        let normal = Self.composite(width: w, height: h, background: background)
        #expect(checker.subjectReachesBottom(
            normal, backdrop: checker.backdropRegion(normal, minimum: 245)
        ))
    }

    /// LESSONS 42: centering must respond to the head moving, not to the planner's arithmetic.
    @Test("centering tracks the head, not the eye midpoint")
    func centeringTracksTheHead() throws {
        let spec = try #require(try Self.specs().first { $0.id == "in-passport" })
        let checker = Self.checker()
        let width = 630

        func face(headCentre: Double, eyeCentre: Double) -> FaceMeasurements {
            FaceMeasurements(
                faceCount: 1, boundingBox: .zero,
                leftEye: CGPoint(x: eyeCentre - 40, y: 300),
                rightEye: CGPoint(x: eyeCentre + 40, y: 300),
                contour: [CGPoint(x: headCentre - 150, y: 300),
                          CGPoint(x: headCentre + 150, y: 300)],
                rawChin: CGPoint(x: headCentre, y: 500), browY: 250,
                yawDeg: 0, pitchDeg: 0, rollDeg: 0,
                captureQuality: nil, eyeOpenness: 0.3, mouthOpenness: 0.02
            )
        }

        // Eyes dead centre, head far off: the case that used to report 0.00%.
        let offset = checker.centeringCheck(
            face(headCentre: 200, eyeCentre: 315), width: width, spec: spec
        )
        #expect(offset.status == .fail, "head 18% off centre reported: \(offset.measured)")
        #expect(!offset.measured.hasPrefix("0.00%"))

        // Head centred, eyes off (a turned head) must still pass.
        let centred = checker.centeringCheck(
            face(headCentre: 315, eyeCentre: 250), width: width, spec: spec
        )
        #expect(centred.status == .pass, "\(centred.measured)")
    }
}
