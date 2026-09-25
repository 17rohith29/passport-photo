import Foundation
import Testing
import TestSupport
@testable import SpecKit

/// Every supported document, checked as a set. A rule an authority states must end up either in
/// the checks or in `status.notEnforced` — never silently absent from both.
@Suite("All documents")
struct AllDocumentsTests {

    static let expected = [
        "in-passport", "us-passport", "eu-schengen-visa", "gb-passport",
        "au-passport", "ca-passport", "cn-visa", "ru-visa",
    ]

    static func all() throws -> [DocumentSpec] {
        let root = try #require(RepoPaths.specs)
        let urls = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? [])
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != "document-spec.schema.json" }
        return try urls.map { try SpecLoader.load(contentsOf: $0) }
            .filter { $0.status.isTestFixture != true }
    }

    @Test("all eight documents load")
    func allLoad() throws {
        let specs = try Self.all()
        #expect(Set(specs.map(\.id)) == Set(Self.expected))
    }

    /// The honesty rule. A green verdict must never be mistaken for full compliance, so anything
    /// the authority states but the app cannot measure has to be written down and shown.
    @Test("every document lists what the app cannot check")
    func everyDocumentDeclaresItsGaps() throws {
        for spec in try Self.all() {
            let notEnforced = spec.status.notEnforced ?? []
            #expect(!notEnforced.isEmpty, "\(spec.id) claims to enforce everything")
            #expect(notEnforced.allSatisfy { !$0.isEmpty }, "\(spec.id) has an empty entry")

            // Glasses are never detected, so any document with a glasses rule must say so.
            if spec.appearance?.glassesAllowed != nil {
                let mentionsGlasses = notEnforced.contains { $0.lowercased().contains("glasses") }
                #expect(mentionsGlasses, "\(spec.id) states a glasses rule but does not admit it is unchecked")
            }
            // Likewise ears: the field is decoded and displayed, never measured.
            if spec.appearance?.earsVisible == true {
                let mentionsEars = notEnforced.contains { $0.lowercased().contains("ear") }
                #expect(mentionsEars, "\(spec.id) requires visible ears but does not admit it is unchecked")
            }
        }
    }

    @Test("every document cites at least one official source")
    func sourcing() throws {
        for spec in try Self.all() {
            #expect(!spec.sources.isEmpty, "\(spec.id) has no sources")
            let official = spec.sources.contains { $0.authority == .official || $0.authority == .officialPartner }
            #expect(official, "\(spec.id) cites no official source")
            // At least one official source must carry quoted text, so the numbers in the spec can
            // be traced back to wording someone actually published. Supporting links need no
            // quote — demanding one would only invite a fabricated quote to satisfy a test.
            let quoted = spec.sources.contains {
                ($0.authority == .official || $0.authority == .officialPartner)
                    && !($0.says ?? "").isEmpty
            }
            #expect(quoted, "\(spec.id) has no official source with quoted text")
        }
    }

    /// A pixel size that does not match the physical aspect stretches every face. GOV.UK's own
    /// figures disagreed this way, so it is checked for all of them.
    @Test("no document stretches the face")
    func aspectRatiosMatch() throws {
        for spec in try Self.all() {
            let mm = spec.photo.sizeMM.width / spec.photo.sizeMM.height
            let px = try #require(spec.photo.digital.outputSizePx)
            let ratio = px.width / px.height
            #expect(abs(ratio - mm) < 0.003,
                    "\(spec.id): \(px.width)x\(px.height) is \(ratio), physical is \(mm)")
        }
    }

    @Test("every head band fits inside its own photo, with room above and below")
    func headBandsAreSane() throws {
        for spec in try Self.all() {
            let band = try #require(HeadHeightBandShim.inMM(spec: spec), "\(spec.id)")
            let height = spec.photo.sizeMM.height
            #expect(band.min > 0, "\(spec.id)")
            #expect(band.max < height, "\(spec.id) head \(band.max) fills the whole \(height) mm photo")
            // Nothing sane asks for a head under a quarter or over 90% of the photo.
            #expect(band.max / height < 0.90, "\(spec.id) head fraction \(band.max / height)")
            #expect(band.min / height > 0.25, "\(spec.id) head fraction \(band.min / height)")
        }
    }

    @Test("the documents really do differ, so none is a copy of another")
    func documentsAreDistinct() throws {
        let specs = try Self.all()
        #expect(Set(specs.map { "\($0.photo.sizeMM.width)x\($0.photo.sizeMM.height)" }).count >= 4)
        #expect(Set(specs.map { $0.background?.colorHex ?? "" }).count >= 3)
        #expect(Set(specs.map { $0.appearance?.glassesAllowed ?? false }).count == 2)
        #expect(Set(specs.map(\.country.code)).count == specs.count)
    }

    @Test("a low-confidence document says why in its notes")
    func lowConfidenceIsExplained() throws {
        for spec in try Self.all() where spec.status.confidence == .low {
            let notes = (spec.status.notes ?? []).joined(separator: " ").lowercased()
            #expect(notes.contains("not") && (notes.contains("verif") || notes.contains("confirm")),
                    "\(spec.id) is low confidence but does not say what was not verified")
        }
    }
}

/// `HeadHeightBand` lives in PhotoPipeline, which SpecKitTests does not depend on.
enum HeadHeightBandShim {
    static func inMM(spec: DocumentSpec) -> SpecKit.Range? {
        let head = spec.geometry.headHeight
        if let mm = head.passMM { return mm }
        if let fraction = head.passFraction {
            return SpecKit.Range(min: fraction.min * spec.photo.sizeMM.height,
                                 max: fraction.max * spec.photo.sizeMM.height)
        }
        return nil
    }
}
