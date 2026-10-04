import CoreGraphics
import Foundation
import SpecKit
import Testing
import TestSupport
@testable import PhotoAnalysis
@testable import PhotoPipeline

/// A check with no rule behind it used to render as a green tick against "requirement: any",
/// which reads exactly like one that was measured and passed. Japan is the first document to
/// reach it: its passport publishes no eye line, and its visa published no top margin.
///
/// This is LESSONS 30's rule from the other side. There, a check that could not RUN had to say
/// so loudly. Here, a check that has nothing to test must not appear at all, because a tick is a
/// claim that something was verified.
@Suite("No rule, no row")
struct NoRuleNoRowTests {

    static func specs() throws -> [DocumentSpec] {
        let dir = try #require(RepoPaths.specs)
        return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.contains("schema") }
            .map { try SpecLoader.load(contentsOf: $0) }
            .filter { $0.status.isTestFixture != true }
            .sorted { $0.id < $1.id }
    }

    static func checker() -> ComplianceChecker {
        ComplianceChecker(analyzer: VisionFaceAnalyzer(), segmenter: VisionSubjectSegmenter())
    }

    static func face(height: Int) -> FaceMeasurements {
        FaceMeasurements(
            faceCount: 1, boundingBox: .zero,
            leftEye: CGPoint(x: 200, y: Double(height) * 0.42),
            rightEye: CGPoint(x: 300, y: Double(height) * 0.42),
            contour: [CGPoint(x: 150, y: 300), CGPoint(x: 350, y: 300)],
            rawChin: CGPoint(x: 250, y: Double(height) * 0.62), browY: Double(height) * 0.3,
            yawDeg: 0, pitchDeg: 0, rollDeg: 0,
            captureQuality: nil, eyeOpenness: 0.3, mouthOpenness: 0.02
        )
    }

    @Test("a document with no eye-line rule produces no eye-line row")
    func noEyeLineRuleNoRow() throws {
        let checker = Self.checker()
        var withRule = 0, without = 0
        for spec in try Self.specs() {
            let geometry = try #require(SpecGeometry(spec: spec), "\(spec.id)")
            let height = Int(geometry.outputSizePx.height)
            let check = checker.eyeLineCheck(
                Self.face(height: height), height: height, geometry: geometry, spec: spec
            )
            if spec.geometry.eyeLine == nil {
                #expect(check == nil, "\(spec.id) states no eye line but emitted a row")
                without += 1
            } else {
                #expect(check != nil, "\(spec.id) states an eye line but emitted no row")
                withRule += 1
            }
        }
        #expect(without > 0, "no document omits an eye line, so this proves nothing")
        #expect(withRule > 0)
    }

    @Test("a document with no top-margin rule produces no top-margin row")
    func noTopMarginRuleNoRow() throws {
        let checker = Self.checker()
        for spec in try Self.specs() {
            let geometry = try #require(SpecGeometry(spec: spec), "\(spec.id)")
            let check = checker.topMarginCheck(crown: 40, geometry: geometry, spec: spec)
            if spec.geometry.topMargin?.passMM == nil {
                #expect(check == nil, "\(spec.id) states no top margin but emitted a row")
            } else {
                #expect(check != nil, "\(spec.id) states a top margin but emitted no row")
            }
        }
    }

    /// The general rule: nothing shown to the user may advertise its requirement as "any".
    @Test("no check tells the user its requirement is 'any'")
    func noCheckClaimsAnyRequirement() async throws {
        guard RepoPaths.hasFixturePhotos else { return }
        let url = try #require(RepoPaths.fixtures).appendingPathComponent("photos/IMG_0012.HEIC")
        let image = try ImageLoader.load(data: try Data(contentsOf: url))
        for spec in try Self.specs() {
            let result = await PassportPipeline().run(image, spec: spec)
            for check in result.allChecks {
                #expect(
                    check.requirement.lowercased() != "any",
                    "\(spec.id) shows \(check.id.rawValue) with requirement 'any'"
                )
            }
        }
    }
}
