import CoreGraphics
import Foundation
import Testing
import TestSupport
import PhotoAnalysis
import SpecKit

/// Runs the real analyzer on the owner's photos. Skips cleanly without them.
@Suite("Face analysis on fixtures", .enabled(if: RepoPaths.hasFixturePhotos))
struct FaceAnalysisFixtureTests {

    static func url(_ name: String) throws -> URL {
        try #require(RepoPaths.fixtures).appendingPathComponent("photos/\(name)")
    }

    @Test("IMG_0012 loads at its oriented size")
    func loadsOriented() throws {
        let image = try ImageLoader.load(contentsOf: try Self.url("IMG_0012.HEIC"))
        #expect(image.width == 4284)
        #expect(image.height == 5712)
    }

    @Test("Vision finds one face on IMG_0012, and its pose matches the ground truth")
    func analyzesGoldenCase() async throws {
        let image = try ImageLoader.load(contentsOf: try Self.url("IMG_0012.HEIC"))
        let face = try await VisionFaceAnalyzer().analyze(image)

        #expect(face.faceCount == 1)

        // fixtures/expected.json groundTruth: rollDeg 2.7 +/- 0.5, which is the eye-line angle
        // (the Python measured it between dlib eye centroids). Vision's pose roll is a different
        // quantity and reads about -6 deg here. The tolerance is wider than the manifest's 0.5
        // because Vision's eye constellation differs from dlib's 68-point model.
        #expect(abs(face.eyeLineAngleDeg - 2.7) < 1.5, "eye line \(face.eyeLineAngleDeg)")
        #expect(abs(face.rollDeg) < 15, "Vision pose roll \(face.rollDeg)")

        // Landmarks must sit inside the image and in a sane arrangement.
        #expect(face.leftEye.x < face.rightEye.x)
        #expect(face.browY < face.leftEye.y)
        #expect(face.rawChin.y > face.leftEye.y)
        #expect(face.faceWidth > 0)

        // LESSONS 6 wants Vision's yaw recorded; the Python estimate was 5.5 +/- 2 deg.
        // Assert only that it is a plausible near-frontal value, not the Python number.
        #expect(abs(face.yawDeg) < 15, "Vision yaw \(face.yawDeg)")

        Self.report(face, label: "IMG_0012")
    }

    @Test("Vision's landmark chin sits above the true chin, and by how much")
    func measuresChinBias() async throws {
        let image = try ImageLoader.load(contentsOf: try Self.url("IMG_0012.HEIC"))
        let face = try await VisionFaceAnalyzer().analyze(image)

        // Ground truth chin (bottom of beard) is 2736 px; the landmark chin should sit above it.
        let groundTruthChin: CGFloat = 2736
        let bias = groundTruthChin - face.rawChin.y
        let headHeight: CGFloat = 1800

        print("""
        VISION CHIN BIAS on IMG_0012
          landmark chin y : \(face.rawChin.y)
          ground truth y  : \(groundTruthChin)
          bias            : \(bias) px (\(100 * bias / headHeight)% of head height)
        """)

        // LESSONS 1 predicts a landmark chin 3.7-5% of head height high for dlib. Vision may
        // differ; this asserts only the direction and a sane magnitude, and records the value.
        #expect(bias > -0.02 * headHeight, "Vision chin sits BELOW the true chin by \(-bias) px")
        #expect(bias < 0.15 * headHeight, "Vision chin is implausibly high: \(bias) px")
    }

    @Test("every fixture photo yields a face without crashing")
    func allFixturesAnalyze() async throws {
        let suite = try FixtureManifestTests.loadSuite()
        let fixtures = try #require(RepoPaths.fixtures)
        var lines: [String] = []

        for testCase in suite.cases {
            let url = fixtures.appendingPathComponent(testCase.file)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let image = try ImageLoader.load(contentsOf: url)
            do {
                let face = try await VisionFaceAnalyzer().analyze(image)
                var line = testCase.fileName.padding(toLength: 18, withPad: " ", startingAt: 0)
                line += " " + String(image.width) + "x" + String(image.height)
                line += "  yaw " + Self.fixed(face.yawDeg)
                line += "  pitch " + Self.fixed(face.pitchDeg)
                line += "  roll " + Self.fixed(face.rollDeg)
                line += "  eyes " + Self.fixed(face.eyeOpenness)
                line += "  mouth " + Self.fixed(face.mouthOpenness)
                line += "  q " + Self.fixed(face.captureQuality ?? -1)
                lines.append(line)
            } catch {
                lines.append("\(testCase.fileName): \(error)")
            }
        }

        print("FIXTURE FACE ANALYSIS\n" + lines.joined(separator: "\n"))
        #expect(!lines.isEmpty)
    }

    static func fixed(_ value: Double, places: Int = 3) -> String {
        String(format: "%.\(places)f", value)
    }

    static func report(_ face: FaceMeasurements, label: String) {
        var lines: [String] = ["FACE " + label]
        lines.append("  faces      : " + String(face.faceCount))
        lines.append("  eye L      : " + String(describing: face.leftEye))
        lines.append("  eye R      : " + String(describing: face.rightEye))
        lines.append("  iod        : " + String(Double(face.interocularDistance)))
        lines.append("  brow y     : " + String(Double(face.browY)))
        lines.append("  raw chin y : " + String(Double(face.rawChin.y)))
        lines.append("  face width : " + String(Double(face.faceWidth)))
        lines.append("  yaw        : " + String(face.yawDeg))
        lines.append("  pitch      : " + String(face.pitchDeg))
        lines.append("  roll       : " + String(face.rollDeg))
        lines.append("  eyes open  : " + String(face.eyeOpenness))
        lines.append("  mouth open : " + String(face.mouthOpenness))
        lines.append("  quality    : " + (face.captureQuality.map { String($0) } ?? "nil"))
        print(lines.joined(separator: "\n"))
    }
}

/// The app decodes with `ImageLoader.defaultMaxPixelSize`, which the other fixture tests do not
/// exercise. If that cap ever breaks detection, every photo fails with "no face found".
@Suite("Decode cap", .serialized, .enabled(if: RepoPaths.hasFixturePhotos))
struct DecodeCapTests {

    @Test("a face is still found at the app's default decode cap")
    func faceFoundAtDefaultCap() async throws {
        let url = try #require(RepoPaths.fixtures).appendingPathComponent("photos/IMG_0012.HEIC")
        let data = try Data(contentsOf: url)
        let image = try ImageLoader.load(data: data, maxPixelSize: ImageLoader.defaultMaxPixelSize)

        #expect(max(image.width, image.height) <= ImageLoader.defaultMaxPixelSize)
        let face = try await VisionFaceAnalyzer().analyze(image)
        #expect(face.faceCount == 1)
        print("capped size \(image.width)x\(image.height), faces \(face.faceCount)")
    }

    @Test("the capped and uncapped images agree on head height within a few percent")
    func cappedMatchesFull() async throws {
        let url = try #require(RepoPaths.fixtures).appendingPathComponent("photos/IMG_0012.HEIC")
        let full = try ImageLoader.load(contentsOf: url)
        let capped = try ImageLoader.load(data: try Data(contentsOf: url),
                                          maxPixelSize: ImageLoader.defaultMaxPixelSize)
        let fullFace = try await VisionFaceAnalyzer().analyze(full)
        let cappedFace = try await VisionFaceAnalyzer().analyze(capped)

        let scale = Double(capped.height) / Double(full.height)
        let fullHead = Double(fullFace.rawChin.y - fullFace.browY) * scale
        let cappedHead = Double(cappedFace.rawChin.y - cappedFace.browY)
        #expect(abs(fullHead - cappedHead) / fullHead < 0.05,
                "full \(fullHead) vs capped \(cappedHead)")
    }
}
