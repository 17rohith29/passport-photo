import Foundation
import Testing
import TestSupport
import SpecKit

/// M0: the manifest and the photos on disk agree. The real per-photo assertions arrive at M2-M4.
@Suite("Fixture manifest")
struct FixtureManifestTests {

    static func loadSuite() throws -> ExpectedSuite {
        let url = try #require(RepoPaths.expectedJSON)
        return try JSONDecoder().decode(ExpectedSuite.self, from: Data(contentsOf: url))
    }

    @Test("expected.json decodes and targets the India passport spec")
    func manifestDecodes() throws {
        let suite = try Self.loadSuite()
        #expect(suite.specId == "in-passport")
        #expect(suite.cases.count == 14)
        #expect(suite.cases.filter { $0.expect == .accept }.count == 1)
        #expect(suite.cases.filter { $0.expect == .reject }.count == 10)
        #expect(suite.cases.filter { $0.expect == .borderline }.count == 3)
    }

    @Test("every reason in the manifest is a known CheckID")
    func reasonsUseTheVocabulary() throws {
        let suite = try Self.loadSuite()
        let vocabulary = Set(suite.checkIdVocabulary)
        for testCase in suite.cases {
            let reasons = (testCase.primaryReasons ?? [])
                + (testCase.alsoAcceptableReasons ?? [])
                + (testCase.allowedWarnings ?? [])
            for reason in reasons {
                #expect(vocabulary.contains(reason), "\(testCase.fileName): unknown check id '\(reason)'")
            }
        }
    }

    @Test("the golden case carries the ground truth M3 will be measured against")
    func goldenCaseHasGroundTruth() throws {
        let suite = try Self.loadSuite()
        let golden = try #require(suite.cases.first { $0.fileName == "IMG_0012.HEIC" })

        #expect(golden.expect == .accept)
        let truth = try #require(golden.groundTruth)
        #expect(truth.orientationApplied == true)
        #expect(truth.imageSizePx == [4284, 5712])

        let crown = try #require(truth.crownYPx)
        let chin = try #require(truth.chinYPx)
        let head = try #require(truth.headHeightPx)
        // chin - crown must agree with the stated head height, inside the tolerances.
        #expect(head.contains(chin.value - crown.value))

        // And that head must clear the spec's required pixels with room to spare.
        let spec = try SpecLoader.load(contentsOf: #require(RepoPaths.inPassportSpec))
        let geometry = try #require(SpecGeometry(spec: spec))
        #expect(head.value > geometry.requiredHeadPx)
    }

    @Test("every reject case names at least one primary reason")
    func rejectsNameAReason() throws {
        let suite = try Self.loadSuite()
        for testCase in suite.cases where testCase.expect == .reject {
            #expect(testCase.primaryReasons?.isEmpty == false, "\(testCase.fileName) has no primaryReasons")
        }
    }

    @Test("every manifest photo exists on disk", .enabled(if: RepoPaths.hasFixturePhotos))
    func photosExist() throws {
        let suite = try Self.loadSuite()
        let fixtures = try #require(RepoPaths.fixtures)
        for testCase in suite.cases {
            let path = fixtures.appendingPathComponent(testCase.file)
            #expect(FileManager.default.fileExists(atPath: path.path), "missing \(testCase.file)")
        }
    }

    @Test("the reference output for the golden case is present", .enabled(if: RepoPaths.hasFixturePhotos))
    func referenceOutputExists() throws {
        let reference = try #require(RepoPaths.fixtures)
            .appendingPathComponent("reference_output/in-passport_IMG_0012.jpg")
        #expect(FileManager.default.fileExists(atPath: reference.path))
    }
}

@Suite("Fixture availability")
struct FixtureAvailabilityTests {

    /// Never fails: `fixtures/photos/` is gitignored, so a fresh clone must still go green.
    @Test("photo-dependent tests skip cleanly when the photos are absent")
    func skipsCleanly() {
        if RepoPaths.hasFixturePhotos {
            #expect(RepoPaths.fixturePhotos != nil)
        } else {
            print("note: skipping photo-dependent fixture tests — \(RepoPaths.skipReason)")
        }
    }
}
