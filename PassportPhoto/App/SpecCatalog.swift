import Foundation
import SpecKit

/// The specs bundled with the app. Countries are data: adding one means adding a JSON file to
/// `specs/`, which the project's synchronized folder picks up with no code change here.
@MainActor
@Observable
final class SpecCatalog {
    private(set) var specs: [DocumentSpec] = []
    private(set) var loadFailures: [String] = []

    init() { reload() }

    func reload() {
        var loaded: [DocumentSpec] = []
        var failures: [String] = []

        for url in Self.bundledSpecURLs() {
            do {
                let spec = try SpecLoader.load(contentsOf: url)
                // Fake specs exist only so tests catch code that assumes 35x45. Never show them.
                guard spec.status.isTestFixture != true else { continue }
                loaded.append(spec)
            } catch {
                failures.append("\(url.lastPathComponent): \(error)")
            }
        }

        // Country, then document. Japan is the first country with two, and the tiebreak was
        // whatever order the files happened to load in, which put its visa above its passport.
        specs = loaded.sorted {
            $0.country.name == $1.country.name
                ? $0.document.displayName < $1.document.displayName
                : $0.country.name < $1.country.name
        }
        loadFailures = failures
    }

    private static func bundledSpecURLs() -> [URL] {
        let all = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        return all.filter { $0.lastPathComponent != "document-spec.schema.json" }
    }
}
