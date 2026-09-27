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
    /// True when the background was kept, so there is no edit to warn about.
    var isUnedited = false
    /// Formats already saved in this session, so we only offer what is still missing.
    var savedVariants: Set<PrintGuidance.Variant> = []
    /// Nil when this document produced no print sheet.
    var otherVariant: PrintGuidance.Variant?
    /// Saves the other format to the same place, without leaving this screen.
    var onSaveOther: () -> Void = {}
    /// Closes the whole flow and returns to Home.
    let onFinish: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingResponsibilities = false

    private var steps: [PrintGuidance.Step] {
        PrintGuidance.steps(
            for: spec, variant: outcome.variant, mode: isUnedited ? .keep : .replace
        )
    }

    private var responsibilities: [String] {
        PrintGuidance.remainingResponsibilities(for: spec, mode: isUnedited ? .keep : .replace)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    // Above the steps, not below them: five confident instructions to print,
                    // cut and submit, followed by "actually they will reject this", is how
                    // someone mails a non-compliant photo to an authority.
                    if !isUnedited, let risk = spec.background?.editingRisk {
                        editingWarning(risk)
                    }
                    nextSteps
                    if !responsibilities.isEmpty { stillUpToYou }
                    finishing

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
                    Button("Finish") { onFinish() }.fontWeight(.semibold)
                }
            }
        }
    }

    /// The other format, offered explicitly.
    ///
    /// Done discards the photo, so the only route to the second format used to be noticing that
    /// "Back to photo" went there. That is not an affordance anyone would find, and re-importing
    /// to get a print sheet you were one tap from is a poor way to end the flow.
    @ViewBuilder
    private var finishing: some View {
        if let other = otherVariant, !savedVariants.contains(other) {
            VStack(alignment: .leading, spacing: 10) {
                Text(other == .sheet
                     ? "Need it on paper as well?"
                     : "Need a single file to upload as well?")
                    .font(.subheadline.weight(.semibold))
                Text(other == .sheet
                     ? "The print sheet lays several copies on one 4 × 6 inch sheet with cut guides."
                     : "The single photo is the one to attach to an online application.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onSaveOther) {
                    Text(other == .sheet ? "Also save the print sheet" : "Also save the single photo")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        } else if savedVariants.count > 1 {
            Label("Both the single photo and the print sheet are saved.",
                  systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, alignment: .leading)
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
            Text("Here is what to do next with your \(spec.country.name) \(spec.document.displayName.lowercased()).")
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
