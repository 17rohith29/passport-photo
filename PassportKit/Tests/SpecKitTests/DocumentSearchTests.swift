import Foundation
import Testing
import TestSupport
@testable import SpecKit

@Suite("Document search")
struct DocumentSearchTests {

    static func all() throws -> [DocumentSpec] {
        let root = try #require(RepoPaths.specs)
        let urls = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? [])
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != "document-spec.schema.json" }
        return try urls.map { try SpecLoader.load(contentsOf: $0) }
            .filter { $0.status.isTestFixture != true }
            .sorted { $0.country.name < $1.country.name }
    }

    static func ids(_ query: String) throws -> Set<String> {
        Set(DocumentSearch.matches(try all(), query: query).map(\.id))
    }

    @Test("an empty query keeps everything, in order")
    func emptyQuery() throws {
        let specs = try Self.all()
        #expect(DocumentSearch.matches(specs, query: "").map(\.id) == specs.map(\.id))
        #expect(DocumentSearch.matches(specs, query: "   ").count == specs.count)
    }

    @Test("a country name finds its document")
    func byCountry() throws {
        #expect(try Self.ids("india") == ["in-passport"])
        #expect(try Self.ids("Canada") == ["ca-passport"])
        #expect(try Self.ids("united kingdom") == ["gb-passport"])
    }

    @Test("case does not matter")
    func caseInsensitive() throws {
        #expect(try Self.ids("CHINA") == Self.ids("china"))
        #expect(try Self.ids("ChInA") == ["cn-visa"])
    }

    @Test("a two-letter country code finds its document")
    func byCode() throws {
        #expect(try Self.ids("GB").contains("gb-passport"))
        #expect(try Self.ids("AU").contains("au-passport"))
        // "US" also appears inside "Russia" and "Australia", which is fine for a search box -
        // it must at least find the United States.
        #expect(try Self.ids("US").contains("us-passport"))
    }

    @Test("a document type narrows to the right kind")
    func byDocumentType() throws {
        let visas = try Self.ids("visa")
        #expect(visas.contains("cn-visa"))
        #expect(visas.contains("ru-visa"))
        #expect(visas.contains("eu-schengen-visa"))
        #expect(!visas.contains("in-passport"))

        let passports = try Self.ids("passport")
        #expect(passports.contains("in-passport"))
        #expect(passports.contains("ca-passport"))
    }

    @Test("a partial word matches")
    func partialWords() throws {
        #expect(try Self.ids("kingd").contains("gb-passport"))
        #expect(try Self.ids("austral").contains("au-passport"))
        #expect(try Self.ids("scheng").contains("eu-schengen-visa"))
    }

    @Test("nonsense matches nothing rather than everything")
    func noMatches() throws {
        #expect(try Self.ids("zzzzz").isEmpty)
        #expect(try Self.ids("Atlantis").isEmpty)
    }

    @Test("accents are ignored in both directions")
    func diacriticInsensitive() throws {
        let specs = [
            DocumentSpecFactory.make(id: "xx-test", country: "Åland Islands", code: "AX"),
        ]
        #expect(DocumentSearch.matches(specs, query: "aland").count == 1)
        #expect(DocumentSearch.matches(specs, query: "Åland").count == 1)
    }

    @Test("every document is reachable by typing its country")
    func everyDocumentIsFindable() throws {
        for spec in try Self.all() {
            let found = DocumentSearch.matches(try Self.all(), query: spec.country.name)
            #expect(found.contains { $0.id == spec.id }, "\(spec.id) cannot be found by its own name")
        }
    }

    /// A country with more than one document must return all of them. Japan is the first, and
    /// "every document is findable by its country name" only asserted a non-empty result.
    @Test("searching a country with two documents returns both")
    func countryWithTwoDocuments() throws {
        let specs = try AllDocumentsTests.all()
        var byCountry: [String: [DocumentSpec]] = [:]
        for spec in specs { byCountry[spec.country.name, default: []].append(spec) }
        let shared = byCountry.filter { $0.value.count > 1 }
        #expect(!shared.isEmpty, "no country has two documents, so this test proves nothing")

        for (country, expected) in shared {
            let found = DocumentSearch.matches(specs, query: country)
            #expect(
                found.count == expected.count,
                "\(country) has \(expected.count) documents but search returned \(found.count)"
            )
            for spec in expected {
                #expect(found.contains { $0.id == spec.id }, "\(spec.id) not found by country name")
            }
        }
    }

    /// And each is reachable by its document type, not only by the country.
    @Test("each document of a shared country is findable by its type")
    func findableByType() throws {
        let specs = try AllDocumentsTests.all()
        let japan = specs.filter { $0.country.code == "JP" }
        #expect(japan.count == 2, "expected a Japanese passport and visa")
        for spec in japan {
            let found = DocumentSearch.matches(specs, query: spec.document.type.rawValue)
            #expect(
                found.contains { $0.id == spec.id },
                "searching '\(spec.document.type.rawValue)' did not find \(spec.id)"
            )
        }
    }

}

/// A minimal spec, for cases the real files do not cover.
enum DocumentSpecFactory {
    static func make(id: String, country: String, code: String) -> DocumentSpec {
        let json = """
        {
          "schemaVersion": 1, "id": "\(id)",
          "country": { "code": "\(code)", "name": "\(country)" },
          "document": { "type": "passport", "displayName": "Passport" },
          "status": { "lastVerified": "2026-09-25", "confidence": "low" },
          "photo": {
            "sizeMM": { "width": 35, "height": 45 },
            "digital": { "sizePx": { "width": 700, "height": 900 }, "format": "jpeg" },
            "print": { "dpi": 300 }
          },
          "geometry": { "headHeight": { "measure": "chinToCrown", "passMM": { "min": 30, "max": 34 } } },
          "sources": [{ "title": "t", "url": "about:blank", "authority": "third-party" }]
        }
        """
        return try! JSONDecoder().decode(DocumentSpec.self, from: Data(json.utf8))
    }
}
