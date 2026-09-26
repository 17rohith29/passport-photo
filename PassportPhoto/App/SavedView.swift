import PhotoPipeline
import SpecKit
import SwiftUI

/// The last screen: what was saved, and what to do with it for this particular document.
///
/// Every country-specific line comes from `PrintGuidance`, which reads the spec. Nothing here
/// knows about any country.
struct SavedView: View {
    let spec: DocumentSpec
    let outcome: SaveOutcome
    /// Closes the whole flow and returns to Home.
    let onFinish: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingResponsibilities = false

    private var steps: [PrintGuidance.Step] {
        PrintGuidance.steps(for: spec, variant: outcome.variant)
    }

    private var responsibilities: [String] {
        PrintGuidance.remainingResponsibilities(for: spec)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    // Above the steps, not below them: five confident instructions to print,
                    // cut and submit, followed by "actually they will reject this", is how
                    // someone mails a non-compliant photo to an authority.
                    if let risk = spec.background?.editingRisk { editingWarning(risk) }
                    nextSteps
                    if !responsibilities.isEmpty { stillUpToYou }
                    Text("This app checks what it can measure. No app can promise an authority will accept a photo.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Saved")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back to photo") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onFinish() }.fontWeight(.semibold)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(outcome.destination.title)
                        .font(.headline)
                    Text(outcome.variant == .single ? "Single photo" : "Print sheet, 4 × 6 in")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Text("\(spec.country.name) \(spec.document.displayName.lowercased()) — here is what to do next.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nextSteps: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 34, height: 34)
                        Image(systemName: step.symbol)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.title).font(.subheadline.weight(.semibold))
                        Text(step.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Step \(index + 1). \(step.title). \(step.detail)")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }

    private func editingWarning(_ risk: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(risk)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private var stillUpToYou: some View {
        DisclosureGroup(isExpanded: $showingResponsibilities) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(responsibilities, id: \.self) { item in
                    Label {
                        Text(item).font(.footnote).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "hand.raised").foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("\(responsibilities.count) things we can't check")
                .font(.subheadline.weight(.medium))
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// What the user just saved, and where it went.
struct SaveOutcome: Identifiable {
    enum Destination {
        case photos
        case files

        var title: String {
            switch self {
            case .photos: "Saved to Photos"
            case .files: "Saved to Files"
            }
        }
    }

    var destination: Destination
    var variant: PrintGuidance.Variant
    var id: String { "\(destination.title)-\(variant.rawValue)" }
}
