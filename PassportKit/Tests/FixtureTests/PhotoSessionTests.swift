import Foundation
import Testing
import TestSupport
import PhotoPipeline
import SpecKit

/// Drives the exact flow the app runs, from imported bytes to a finished result. This is what
/// catches "I picked a photo and it just spins".
@Suite("Photo session flow", .serialized, .enabled(if: RepoPaths.hasFixturePhotos))
struct PhotoSessionTests {

    static func data(_ name: String) throws -> Data {
        let url = try #require(RepoPaths.fixtures).appendingPathComponent("photos/\(name)")
        return try Data(contentsOf: url)
    }

    static func spec() throws -> DocumentSpec {
        try SpecLoader.load(contentsOf: #require(RepoPaths.inPassportSpec))
    }

    @MainActor
    @Test("a good photo runs to a finished result, ticking off every stage")
    func acceptedPhotoFinishes() async throws {
        let session = PhotoSession()
        #expect(session.phase == .idle)

        await session.processAndWait(data: try Self.data("IMG_0012.HEIC"), spec: try Self.spec())

        #expect(session.phase == .finished)
        #expect(session.output != nil)
        // The result screen never reads the source, and at the retry cap it is ~147 MB, so it
        // is released as soon as a result exists.
        #expect(session.sourceImage == nil)
        #expect(session.loadError == nil)

        // Every stage must end up ticked: a stage that never completes is the spinner bug.
        for stage in PipelineStage.allCases {
            #expect(session.completed.contains(stage), "stage never completed: \(stage.rawValue)")
        }
        #expect(session.failures.isEmpty)
    }

    @MainActor
    @Test("the reading stage completes before the pipeline starts")
    func readingCompletesEarly() async throws {
        let session = PhotoSession()
        await session.processAndWait(data: try Self.data("IMG_0012.HEIC"), spec: try Self.spec())
        // `reading` is ticked as soon as the image decodes, not only at the very end.
        #expect(session.completed.contains(.reading))
    }

    @MainActor
    @Test("a rejected photo lands on the rejection phase with a reason to show")
    func rejectedPhotoExplainsItself() async throws {
        let session = PhotoSession()
        await session.processAndWait(data: try Self.data("IMG_0010.HEIC"), spec: try Self.spec())

        #expect(session.phase == .rejected)
        #expect(session.output == nil)
        #expect(!session.failures.isEmpty)
        // The rejection screen needs something to say for every failure.
        for failure in session.failures {
            #expect(!failure.measured.isEmpty)
            #expect(!failure.requirement.isEmpty)
            #expect(failure.userMessage?.isEmpty == false, "\(failure.id.rawValue) has no advice")
        }
    }

    @MainActor
    @Test("unreadable data fails cleanly instead of hanging")
    func garbageDataDoesNotHang() async throws {
        let session = PhotoSession()
        await session.processAndWait(data: Data([0x00, 0x01, 0x02, 0x03]), spec: try Self.spec())

        #expect(session.phase == .rejected)
        #expect(session.loadError != nil)
        #expect(session.output == nil)
    }

    @MainActor
    @Test("reset clears everything so the next photo starts fresh")
    func resetClears() async throws {
        let session = PhotoSession()
        await session.processAndWait(data: try Self.data("IMG_0012.HEIC"), spec: try Self.spec())
        #expect(session.phase == .finished)

        session.reset()
        #expect(session.phase == .idle)
        #expect(session.completed.isEmpty)
        #expect(session.result == nil)
        #expect(session.sourceImage == nil)
        #expect(session.loadError == nil)
    }

    @MainActor
    @Test("the finished result carries everything the result screen renders")
    func resultIsRenderable() async throws {
        let session = PhotoSession()
        await session.processAndWait(data: try Self.data("IMG_0012.HEIC"), spec: try Self.spec())

        let output = try #require(session.output)
        #expect(output.digital.width == 630)
        #expect(output.digital.height == 810)
        #expect(!output.digitalJPEG.isEmpty)
        #expect(output.printSheet != nil, "the Print sheet tab would be empty")
        #expect(output.printSheetJPEG?.isEmpty == false)
        #expect(session.result?.verdict == .meetsRequirements)
        #expect(!session.checks.isEmpty)
    }
}
