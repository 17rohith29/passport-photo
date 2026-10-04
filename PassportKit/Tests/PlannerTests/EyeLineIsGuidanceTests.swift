import Foundation
import SpecKit
import Testing
import TestSupport
@testable import PhotoAnalysis
@testable import PhotoPipeline

/// The eye-line bands are ours, not any authority's. GOV.UK, canada.ca, the EU Commission
/// guidance and the Warsaw consulate page publish no eye-line position, and the US spec says so
/// in its own note. An app-invented number must not reject a photo an authority would accept.
@Suite("Eye line is guidance, not a rule")
struct EyeLineIsGuidanceTests {

    static func specs() throws -> [DocumentSpec] {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("specs")
        return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.contains("schema") }
            .map { try SpecLoader.load(contentsOf: $0) }
            .filter { $0.status.isTestFixture != true }
    }

    @Test("an eye line far outside the band warns instead of failing")
    func farOutsideTheBandOnlyWarns() throws {
        let checker = ComplianceChecker(
            analyzer: VisionFaceAnalyzer(), segmenter: VisionSubjectSegmenter()
        )
        for spec in try Self.specs() where spec.geometry.eyeLine != nil {
            let geometry = try #require(SpecGeometry(spec: spec), "\(spec.id)")
            let height = Int(geometry.outputSizePx.height)
            // Eyes almost at the bottom of the frame: as far outside any band as it gets.
            var face = FaceMeasurements(
                faceCount: 1, boundingBox: .zero,
                leftEye: CGPoint(x: 100, y: Double(height) * 0.95),
                rightEye: CGPoint(x: 200, y: Double(height) * 0.95),
                contour: [], rawChin: .zero, browY: 0,
                yawDeg: 0, pitchDeg: 0, rollDeg: 0,
                captureQuality: nil, eyeOpenness: 0.3, mouthOpenness: 0.02
            )
            let low = try #require(checker.eyeLineCheck(face, height: height, geometry: geometry, spec: spec), "\(spec.id)")
            #expect(low.status != .fail, "\(spec.id) failed a photo on our own eye-line band")

            face.leftEye.y = Double(height) * 0.02
            face.rightEye.y = Double(height) * 0.02
            let high = try #require(checker.eyeLineCheck(face, height: height, geometry: geometry, spec: spec), "\(spec.id)")
            #expect(high.status != .fail, "\(spec.id) failed a photo on our own eye-line band")
        }
    }

    /// It must still be reported: guidance that says nothing is not guidance.
    @Test("an out-of-band eye line is still surfaced, with an honest requirement string")
    func stillReported() throws {
        let checker = ComplianceChecker(
            analyzer: VisionFaceAnalyzer(), segmenter: VisionSubjectSegmenter()
        )
        let spec = try #require(try Self.specs().first { $0.id == "in-passport" })
        let geometry = try #require(SpecGeometry(spec: spec))
        let height = Int(geometry.outputSizePx.height)
        let face = FaceMeasurements(
            faceCount: 1, boundingBox: .zero,
            leftEye: CGPoint(x: 100, y: Double(height) * 0.95),
            rightEye: CGPoint(x: 200, y: Double(height) * 0.95),
            contour: [], rawChin: .zero, browY: 0,
            yawDeg: 0, pitchDeg: 0, rollDeg: 0,
            captureQuality: nil, eyeOpenness: 0.3, mouthOpenness: 0.02
        )
        let check = try #require(checker.eyeLineCheck(face, height: height, geometry: geometry, spec: spec))
        #expect(check.status == .warn)
        #expect(check.userMessage?.isEmpty == false)
        #expect(check.requirement.contains("not a stated rule"))
    }
}
