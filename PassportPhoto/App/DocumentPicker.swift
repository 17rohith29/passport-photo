import SpecKit
import SwiftUI

/// Picking one of many documents. A card per document stopped scaling at eight — it pushed the
/// main action below the fold — so the selected one is shown and the rest live behind a
/// searchable list that works just as well at fifty.
struct DocumentPickerSheet: View {
    let specs: [DocumentSpec]
    let selectedID: String
    let onSelect: (DocumentSpec) -> Void

    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if matches.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    ForEach(matches) { spec in
                        Button {
                            onSelect(spec)
                            dismiss()
                        } label: {
                            DocumentRow(spec: spec, isSelected: spec.id == selectedID)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.plain)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Country or document"
            )
            .navigationTitle("Choose a document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var matches: [DocumentSpec] {
        DocumentSearch.matches(specs, query: query)
    }
}

struct DocumentRow: View {
    let spec: DocumentSpec
    let isSelected: Bool

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 12) {
            if !typeSize.isAccessibilitySize {
                Text(DocumentStyle.flag(for: spec.country.code))
                    .font(.title2)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(spec.country.name), \(spec.document.displayName)")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(DocumentStyle.summary(for: spec))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
                    .fontWeight(.semibold)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Shared between the picker row and the home card so they never drift apart.
enum DocumentStyle {
    static func summary(for spec: DocumentSpec) -> String {
        let size = "\(trim(spec.photo.sizeMM.width)) × \(trim(spec.photo.sizeMM.height)) mm"
        switch spec.background?.colorHex.uppercased() {
        case "#FFFFFF": return "\(size), white background"
        case .none: return size
        default: return "\(size), light background"
        }
    }

    static func trim(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%g", value)
    }

    /// Regional indicator symbols from the ISO country code.
    static func flag(for code: String) -> String {
        let base: UInt32 = 127397
        var result = ""
        for scalar in code.unicodeScalars {
            if let value = UnicodeScalar(base + scalar.value) { result.unicodeScalars.append(value) }
        }
        return result.isEmpty ? "🏳️" : result
    }
}
