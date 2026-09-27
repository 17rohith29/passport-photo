import PhotoPipeline
import SpecKit
import SwiftUI
import UniformTypeIdentifiers

struct ResultView: View {
    let session: PhotoSession
    let saver: PhotoSaver
    let spec: DocumentSpec

    /// The two things a user can walk away with. `PrintGuidance.Variant` is the shared name for
    /// these, so the advice on the Saved screen matches what was actually saved.
    typealias Variant = PrintGuidance.Variant

    @State private var variant: Variant = .single
    @State private var savedOutcome: SaveOutcome?
    /// The variant captured at the moment a save began. Reading `variant` at completion let the
    /// user switch the segmented control mid-save and get advice for a file they never saved.
    @State private var savingVariant: Variant?
    /// What has actually been written, so the Saved screen offers only what is missing.
    @State private var savedVariants: Set<Variant> = []
    /// Set when "also save the other format" chose Files. The exporter cannot be presented in
    /// the same update that dismisses the Saved sheet: two presentations in one transaction is
    /// the bug HomeView already carries a comment about, and a dropped one would leave
    /// `exporting` stuck true, killing every later Save to Files.
    @State private var pendingExport: Variant?
    /// The last outcome shown, so a cancelled export can put the screen back.
    @State private var lastOutcome: SaveOutcome?
    @State private var showingMeasurements = false
    @State private var showingChecks = false
    @State private var exporting = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                photo
                verdictPill

                Picker("Output", selection: $variant) {
                    ForEach(Variant.allCases, id: \.self) { option in
                        Text(Self.label(for: option)).tag(option)
                            .disabled(data(for: option) == nil)
                    }
                }
                .pickerStyle(.segmented)

                Toggle(
                    variant == .single ? "Measurements" : "Measurements (single photo only)",
                    isOn: $showingMeasurements
                )
                .toggleStyle(.switch)
                .disabled(variant != .single)

                if session.isUnedited {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.seal")
                            .foregroundStyle(.green)
                            .accessibilityHidden(true)
                        Text("Your own background was kept. This photo was cropped, straightened and resized. It was not sharpened or retouched, so it is not an edited photo. That is one of \(spec.country.name)'s rules. The rest are still yours to meet.")
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityElement(children: .combine)
                } else if let risk = spec.background?.editingRisk {
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

                saveMenu
                saveStatus
            }
            .padding()
        }
        .task {
            if data(for: variant) == nil, data(for: .single) != nil { variant = .single }
        }
        .navigationTitle("Your photo")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingChecks) {
            ChecksSheet(checks: session.checks)
        }
        .fileExporter(
            isPresented: $exporting,
            document: JPEGDocument(data: currentData ?? Data()),
            contentType: .jpeg,
            defaultFilename: filename
        ) { result in
            guard let saved = savingVariant else { return }
            savingVariant = nil
            if case .success = result {
                savedVariants.insert(saved)
                record(SaveOutcome(destination: .files, variant: saved))
            } else {
                // Cancelled. Put the guidance for the file they did save back on screen
                // instead of dropping them on the result with no way back to it.
                savedOutcome = lastOutcome
            }
        }
        // Saving to Photos finishes asynchronously, so the end screen follows the saver's state
        // rather than the button tap.
        .onChange(of: saver.state) { _, state in
            guard state == .savedToPhotos, let saved = savingVariant else { return }
            savingVariant = nil
            savedVariants.insert(saved)
            record(SaveOutcome(destination: .photos, variant: saved))
        }
        // Switching output after a save makes the green "Saved" row a lie: what is in Photos is
        // the other file. Clear it rather than leave it pointing at the wrong thing.
        .onChange(of: variant) { _, _ in
            // Leave a save that is already running alone. Clearing it here made the completion
            // record the format the user had just switched to rather than the one written.
            guard saver.state != .saving, savingVariant == nil else { return }
            saver.reset()
        }
        .sheet(item: $savedOutcome, onDismiss: {
            // Present the exporter only once the sheet has actually gone.
            if let target = pendingExport {
                pendingExport = nil
                variant = target
                savingVariant = target
                exporting = true
            }
        }) { outcome in
            SavedView(
                spec: spec, outcome: outcome, isUnedited: session.isUnedited,
                savedVariants: savedVariants,
                otherVariant: otherVariant(after: outcome.variant),
                onSaveOther: { saveOther(after: outcome) },
                onFinish: {
                    savedOutcome = nil
                    session.reset()
                    saver.reset()
                }
            )
        }
    }

    @ViewBuilder
    private var photo: some View {
        if let image = currentImage {
            ZStack {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                if showingMeasurements, variant == .single, let output = session.output {
                    MeasurementOverlay(output: output, spec: spec)
                }
            }
            .frame(maxHeight: 460)
            // A neutral backdrop so the photo's own white background reads as part of it.
            .padding(10)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var verdictPill: some View {
        let verdict = session.result?.verdict ?? .cannotUse
        return Button {
            showingChecks = true
        } label: {
            HStack {
                Image(systemName: Self.symbol(for: verdict))
                Text(verdict.headline)
                Image(systemName: "chevron.right").font(.caption)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            // 44pt minimum: this is the control that opens the full check list.
            .frame(minHeight: 44)
            .background(Self.tint(for: verdict).opacity(0.18), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    static func symbol(for verdict: Verdict) -> String {
        switch verdict {
        case .meetsRequirements: "checkmark.seal.fill"
        case .meetsRequirementsWithWarnings: "exclamationmark.triangle.fill"
        case .cannotUse: "xmark.seal.fill"
        }
    }

    static func tint(for verdict: Verdict) -> Color {
        switch verdict {
        case .meetsRequirements: .green
        case .meetsRequirementsWithWarnings: .orange
        case .cannotUse: .red
        }
    }

    private var saveMenu: some View {
        Menu {
            Button("Save to Photos") {
                guard let data = currentData else { return }
                savingVariant = variant
                saver.saveToPhotos(data)
            }
            Button("Save to Files") {
                savingVariant = variant
                exporting = true
            }
        } label: {
            Label("Save", systemImage: "square.and.arrow.down")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    @ViewBuilder
    private var saveStatus: some View {
        switch saver.state {
        case .none:
            EmptyView()
        case .saving:
            ProgressView()
        case .savedToPhotos:
            Button {
                savedOutcome = SaveOutcome(destination: .photos, variant: savingVariant ?? variant)
            } label: {
                HStack(spacing: 6) {
                    Label("Saved to Photos", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("See next steps").font(.footnote).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        case .permissionDenied:
            Text("Photos access was declined. You can still use Save to Files, or allow adding photos in Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case let .failed(message):
            Text(message).font(.footnote).foregroundStyle(.red)
        }
    }

    private var currentImage: CGImage? {
        guard let output = session.output else { return nil }
        return variant == .single ? output.digital : output.printSheet
    }

    private var currentData: Data? {
        guard let output = session.output else { return nil }
        return variant == .single ? output.digitalJPEG : output.printSheetJPEG
    }

    /// The format not yet saved, or nil when this document produced only one.
    private func otherVariant(after saved: Variant) -> Variant? {
        let other: Variant = saved == .single ? .sheet : .single
        guard data(for: other) != nil else { return nil }
        return other
    }

    private func data(for variant: Variant) -> Data? {
        guard let output = session.output else { return nil }
        return variant == .single ? output.digitalJPEG : output.printSheetJPEG
    }

    private func record(_ outcome: SaveOutcome) {
        lastOutcome = outcome
        savedOutcome = outcome
    }

    /// Saves the other format to wherever the first one went, without leaving the flow.
    private func saveOther(after outcome: SaveOutcome) {
        guard let other = otherVariant(after: outcome.variant), savingVariant == nil else { return }
        switch outcome.destination {
        case .photos:
            // No reset here. `saveToPhotos` sets .saving first, which is already a change, so
            // onChange still fires - and resetting would disarm the in-flight guard that stops
            // two quick taps writing two assets. The sheet stays up and updates when the new
            // outcome lands.
            variant = other
            savingVariant = other
            guard let data = data(for: other) else { savingVariant = nil; return }
            saver.saveToPhotos(data)
        case .files:
            // Deferred: see `pendingExport`.
            pendingExport = other
            savedOutcome = nil
        }
    }

    static func label(for variant: Variant) -> String {
        switch variant {
        case .single: "Single photo"
        case .sheet: "Print sheet"
        }
    }

    private var filename: String {
        let base = spec.id
        return variant == .single ? "\(base)-photo" : "\(base)-print-4x6"
    }
}

/// Crown, chin and eye lines over the finished photo, with a mm scale.
struct MeasurementOverlay: View {
    let output: RenderedOutput
    let spec: DocumentSpec

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            // These are where the crown and chin actually landed, not the spec's targets.
            let headMM = SpecGeometry(spec: spec).map {
                $0.pxToMM(Double(output.digital.height) * (output.chinFraction - output.crownFraction))
            } ?? 0

            ZStack(alignment: .topLeading) {
                line(at: output.crownFraction, in: size, label: "crown")
                line(at: output.chinFraction, in: size, label: "chin")
                Text(String(format: "head %.1f mm", headMM))
                    .font(.caption2.bold())
                    .padding(4)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
                    .position(
                        x: size.width - 52,
                        y: size.height * (output.crownFraction + output.chinFraction) / 2
                    )
            }
            .allowsHitTesting(false)
        }
    }

    private func line(at fraction: Double, in size: CGSize, label: String) -> some View {
        let y = size.height * fraction
        return ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: size.width, height: 1)
            Text(label)
                .font(.caption2)
                .padding(.horizontal, 4)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 3))
                .offset(x: 4, y: -9)
        }
        .position(x: size.width / 2, y: y)
    }
}

struct ChecksSheet: View {
    let checks: [CheckResult]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Checks") {
                    ForEach(checks) { CheckRow(check: $0) }
                }
            }
            .navigationTitle("All checks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
