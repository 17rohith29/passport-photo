import Foundation

/// Matching for the document picker. Pure, and in the package rather than the view, because
/// search is easy to get subtly wrong — case, accents, country codes — and none of that is
/// testable from inside a SwiftUI sheet.
public enum DocumentSearch {

    /// Documents matching `query`, in the order given. An empty query matches everything.
    ///
    /// Matches the country name, the two-letter code, the document's display name and its type,
    /// so "GB", "united", "visa" and "passport" all find something. Case- and
    /// diacritic-insensitive, so "aland" finds "Åland".
    public static func matches(_ specs: [DocumentSpec], query: String) -> [DocumentSpec] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return specs }

        return specs.filter { spec in
            haystack(for: spec).range(
                of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]
            ) != nil
        }
    }

    static func haystack(for spec: DocumentSpec) -> String {
        [
            spec.country.name,
            spec.country.code,
            spec.document.displayName,
            spec.document.type.rawValue,
            spec.document.channel ?? "",
        ].joined(separator: " ")
    }
}
