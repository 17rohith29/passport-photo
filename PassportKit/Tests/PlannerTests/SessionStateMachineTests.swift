import CoreGraphics
import Foundation
import ImageIO
import SpecKit
import Testing
import UniformTypeIdentifiers
@testable import PhotoAnalysis
@testable import PhotoPipeline

/// The session's state machine, driven with fakes: no photos, no Vision, no device. Every bug
/// these cover was reachable without any of those, and none of them had a test.
@Suite("Session state machine", .serialized)
struct SessionStateMachineTests {

    /// A face that measures plausibly, so the pipeline gets past the input gate.
    static func face(in size: CGSize) -> FaceMeasurements {
        let w = size.width, h = size.height
        return FaceMeasurements(
            faceCount: 1,
            boundingBox: CGRect(x: w * 0.3, y: h * 0.2, width: w * 0.4, height: h * 0.45),
            leftEye: CGPoint(x: w * 0.42, y: h * 0.36),
            rightEye: CGPoint(x: w * 0.58, y: h * 0.36),
            contour: (0..<24).map { i in
                let t = Double(i) / 24 * 2 * .pi
                return CGPoint(x: w * 0.5 + cos(t) * w * 0.2, y: h * 0.42 + sin(t) * h * 0.22)
            },
            rawChin: CGPoint(x: w * 0.5, y: h * 0.64), browY: h * 0.28,
            yawDeg: 0, pitchDeg: 0, rollDeg: 0,
            captureQuality: 0.9, eyeOpenness: 0.3, mouthOpenness: 0.02
        )
    }

    struct SlowAnalyzer: FaceAnalyzing {
        let delay: Duration
        func analyze(_ image: CGImage) async throws -> FaceMeasurements {
            try await Task.sleep(for: delay)
            return SessionStateMachineTests.face(
                in: CGSize(width: image.width, height: image.height)
            )
        }
    }

    struct PlainAnalyzer: FaceAnalyzing {
        func analyze(_ image: CGImage) async throws -> FaceMeasurements {
            SessionStateMachineTests.face(in: CGSize(width: image.width, height: image.height))
        }
    }

    /// A matte that is subject in the middle and background at the edges.
    struct OvalSegmenter: SubjectSegmenting {
        func matte(for image: CGImage) async throws -> AlphaMatte {
            var m = AlphaMatte(width: image.width, height: image.height, repeating: 0)
            let cx = Double(image.width) / 2, cy = Double(image.height) * 0.45
            let rx = Double(image.width) * 0.26, ry = Double(image.height) * 0.30
            for y in 0..<image.height {
                for x in 0..<image.width {
                    let dx = (Double(x) - cx) / rx, dy = (Double(y) - cy) / ry
                    m[x, y] = dx * dx + dy * dy <= 1 ? 1 : 0
                }
            }
            return m
        }
    }

    static func jpeg(width: Int, height: Int) throws -> Data {
        var pixels = PixelImage(width: width, height: height, fill: (250, 250, 250))
        for y in 0..<height {
            for x in 0..<width where (x / 7 + y / 7) % 2 == 0 {
                let o = pixels.offset(x: x, y: y)
                pixels.pixels[o] = 120; pixels.pixels[o + 1] = 110; pixels.pixels[o + 2] = 100
            }
        }
        let image = try #require(ImageConversion.cgImage(from: pixels))
        return try #require(JPEGExporter.encode(image, dpi: 300, fileSizeKB: nil)).data
    }

    static func spec() throws -> DocumentSpec {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("specs")
        return try SpecLoader.load(contentsOf: dir.appendingPathComponent("in-passport.json"))
    }

    @MainActor
    static func session(analyzer: some FaceAnalyzing) -> PhotoSession {
        PhotoSession(pipeline: PassportPipeline(analyzer: analyzer, segmenter: OvalSegmenter()))
    }

    /// Cancelling used to leave the abandoned run's stage reports driving the NEXT photo's
    /// progress screen: the second import ticked green to the end and then sat there, because
    /// its own run had not started yet.
    @MainActor
    @Test("a cancelled run cannot drive the next run's progress")
    func cancelledRunDoesNotDriveTheNextOne() async throws {
        let session = Self.session(analyzer: SlowAnalyzer(delay: .milliseconds(400)))
        let spec = try Self.spec()
        let data = try Self.jpeg(width: 900, height: 1200)

        session.process(data: data, spec: spec)
        try await Task.sleep(for: .milliseconds(120))
        session.cancel()
        session.reset()
        #expect(session.phase == .idle)
        #expect(session.completed.isEmpty)

        // The abandoned run is still finishing inside the actor. Nothing it reports from here
        // may touch the session again.
        try await Task.sleep(for: .milliseconds(600))
        #expect(session.phase == .idle, "a cancelled run moved the session out of idle")
        #expect(session.completed.isEmpty, "a cancelled run ticked stages after being cancelled")
    }

    @MainActor
    @Test("cancelling mid-run leaves the session idle, not half finished")
    func cancelMidRun() async throws {
        let session = Self.session(analyzer: SlowAnalyzer(delay: .milliseconds(300)))
        session.process(data: try Self.jpeg(width: 900, height: 1200), spec: try Self.spec())
        try await Task.sleep(for: .milliseconds(80))
        session.cancel()
        try await Task.sleep(for: .milliseconds(500))
        #expect(session.result == nil)
        #expect(session.output == nil)
    }

    /// The bug: `phase` branched on whether pixels existed, so a photo the app had judged
    /// `.cannotUse` still reached the result screen, under a prominent Save button.
    @MainActor
    @Test("a cannotUse verdict never reaches the finished phase")
    func cannotUseIsAlwaysRejected() async throws {
        let session = Self.session(analyzer: PlainAnalyzer())
        await session.processAndWait(
            data: try Self.jpeg(width: 900, height: 1200), spec: try Self.spec()
        )
        if session.phase == .finished {
            let verdict = try #require(session.result?.verdict)
            #expect(verdict != .cannotUse, "a cannotUse photo reached the result screen")
            #expect(session.failures.isEmpty, "the result screen was shown with failing checks")
        } else {
            #expect(session.phase == .rejected)
        }
    }

    /// Whatever the verdict, the two must agree: a finished session must have no failures.
    @MainActor
    @Test("finished and rejected are decided by the verdict, not by whether a render happened")
    func phaseFollowsVerdict() async throws {
        for size in [(900, 1200), (700, 900), (1200, 1600)] {
            let session = Self.session(analyzer: PlainAnalyzer())
            await session.processAndWait(
                data: try Self.jpeg(width: size.0, height: size.1), spec: try Self.spec()
            )
            switch session.phase {
            case .finished:
                #expect(session.result?.verdict != .cannotUse, "\(size)")
                #expect(session.output != nil, "\(size)")
            case .rejected:
                break
            default:
                Issue.record("session ended in \(session.phase) for \(size)")
            }
        }
    }

    /// The result screen never reads the source image, and at the retry cap it is ~147 MB.
    @MainActor
    @Test("the source image is released once a result is on screen")
    func sourceReleasedWhenFinished() async throws {
        let session = Self.session(analyzer: PlainAnalyzer())
        await session.processAndWait(
            data: try Self.jpeg(width: 900, height: 1200), spec: try Self.spec()
        )
        if session.phase == .finished {
            #expect(session.sourceImage == nil, "a finished session still holds the source image")
        }
    }

    @MainActor
    @Test("reset clears everything, so a second photo starts clean")
    func resetIsComplete() async throws {
        let session = Self.session(analyzer: PlainAnalyzer())
        await session.processAndWait(
            data: try Self.jpeg(width: 900, height: 1200), spec: try Self.spec()
        )
        session.reset()
        #expect(session.phase == .idle)
        #expect(session.completed.isEmpty)
        #expect(session.result == nil)
        #expect(session.sourceImage == nil)
        #expect(session.loadError == nil)
        #expect(session.output == nil)
    }
}
