import PhotoPipeline
import SpecKit
import SwiftUI

/// Everything here is read from the spec JSON — no requirement is written in Swift.
struct RequirementsSheet: View {
    let spec: DocumentSpec
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("The photo") {
                    row("Size", "\(trim(spec.photo.sizeMM.width)) × \(trim(spec.photo.sizeMM.height)) mm")
                    if let px = spec.photo.digital.outputSizePx {
                        row("For upload", "\(trim(px.width)) × \(trim(px.height)) pixels, JPEG")
                    }
                    if let kb = spec.photo.digital.fileSizeKB {
                        row("File size", "\(trim(kb.min))–\(trim(kb.max)) KB")
                    }
                }

                Section("You in it") {
                    // Specs state these in different units: India gives millimetres and a
                    // fraction eye line, the US millimetres both ways, the EU a percentage for
                    // the head. Reading only one form hid each country's rules in turn.
                    if let band = HeadHeightBand.inMM(spec: spec) {
                        row("Head height", "\(trim(band.min))–\(trim(band.max)) mm, chin to crown")
                    }
                    if let eye = spec.geometry.eyeLine?.fromBottomFraction {
                        row("Eye line", "\(trim(eye.min * 100))–\(trim(eye.max * 100))% up from the bottom")
                    } else if let eye = spec.geometry.eyeLine?.fromBottomMM {
                        row("Eye line", "\(trim(eye.min))–\(trim(eye.max)) mm up from the bottom")
                    }
                    if let appearance = spec.appearance {
                        if appearance.eyesOpen == true { row("Eyes", "Open, looking at the camera") }
                        if appearance.mouthClosed == true { row("Mouth", "Closed") }
                        if let expression = appearance.expression {
                            row("Expression", expression == .neutral ? "Neutral" : "Neutral or a slight smile")
                        }
                        if let glasses = appearance.glassesAllowed {
                            row("Glasses", glasses ? "Allowed" : "Not allowed")
                        }
                    }
                    if let hex = spec.background?.colorHex {
                        row("Background", hex.uppercased() == "#FFFFFF" ? "Plain white" : "Plain light grey (\(hex))")
                    }
                }

                // A green verdict must never be mistaken for full compliance. These are rules the
                // authority states that the app cannot measure, listed by the spec itself.
                if let notEnforced = spec.status.notEnforced, !notEnforced.isEmpty {
                    Section {
                        ForEach(notEnforced, id: \.self) { item in
                            Label {
                                Text(item)
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: "eye.slash")
                                    .foregroundStyle(.orange)
                            }
                        }
                    } header: {
                        Text("What we can't check")
                    } footer: {
                        Text("The app measures everything above this section. These rules are still yours to meet.")
                            .font(.caption)
                    }
                }

                Section {
                    ForEach(Array(spec.sources.enumerated()), id: \.offset) { _, source in
                        if let url = URL(string: source.url), source.url != "about:blank" {
                            Link(destination: url) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(source.title).font(.subheadline)
                                    Text(authority(source.authority))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Text(source.title).font(.subheadline)
                        }
                    }
                } header: {
                    Text("Where this comes from")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Last verified \(formatted(spec.status.lastVerified)). Confidence: \(spec.status.confidence.rawValue).")
                        ForEach(spec.status.notes ?? [], id: \.self) { note in
                            Text(note)
                        }
                        // Never claim guaranteed acceptance.
                        Text("This app checks your photo against the measurements above. It can't guarantee any authority will accept it.")
                            .padding(.top, 4)
                    }
                    .font(.caption)
                }
            }
            .navigationTitle("Requirements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
    }

    private func authority(_ value: Source.Authority) -> String {
        switch value {
        case .official: return "Official"
        case .officialPartner: return "Official partner"
        case .thirdParty: return "Third party"
        }
    }

    private func formatted(_ iso: String) -> String {
        guard let date = spec.status.lastVerifiedDate else { return iso }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func trim(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%g", value)
    }
}
