import PhotoPipeline
import SpecKit
import SwiftUI
import UniformTypeIdentifiers

struct ResultView: View {
    let session: PhotoSessionModel
    let spec: DocumentSpec

    enum Variant: String, CaseIterable { case upload = "Upload file", print = "Print sheet" }

    @State private var variant: Variant = .upload
    @State private var showingMeasurements = false
    @State private var showingChecks = false
    @State private var exporting = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                photo
                verdictPill

                Picker("Output", selection: $variant) {
                    ForEach(Variant.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Toggle("Measurements", isOn: $showingMeasurements)
                    .toggleStyle(.switch)

                if let risk = spec.background?.editingRisk {
                    Text(risk)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                saveMenu
                saveStatus
            }
            .padding()
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
        ) { _ in }
    }

    @ViewBuilder
    private var photo: some View {
        if let image = currentImage {
            ZStack {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                if showingMeasurements, variant == .upload, let output = session.output {
                    MeasurementOverlay(output: output, spec: spec)
                }
            }
            .frame(maxHeight: 460)
            // A neutral backdrop so the photo's own white background reads as part of it.
            .padding(10)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var verdictPill: some View {
        let verdict = session.result?.verdict ?? .cannotUse
        return Button {
            showingChecks = true
        } label: {
            HStack {
                Image(systemName: verdict == .meetsRequirements ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                Text(verdict.headline)
                Image(systemName: "chevron.right").font(.caption)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                (verdict == .meetsRequirements ? Color.green : Color.orange).opacity(0.18),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }

    private var saveMenu: some View {
        Menu {
            Button("Save to Photos") {
                if let data = currentData { session.saveToPhotos(data) }
            }
            Button("Save to Files") { exporting = true }
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
        switch session.saveState {
        case .none:
            EmptyView()
        case .saving:
            ProgressView()
        case .savedToPhotos:
            VStack(alignment: .leading, spacing: 6) {
                Label("Saved to Photos", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Printing: order a standard 4 × 6 in print, not the store's passport service. Turn off crop, zoom and enhance, and measure one photo before cutting.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        return variant == .upload ? output.digital : (output.printSheet ?? output.digital)
    }

    private var currentData: Data? {
        guard let output = session.output else { return nil }
        return variant == .upload ? output.digitalJPEG : (output.printSheetJPEG ?? output.digitalJPEG)
    }

    private var filename: String {
        let base = spec.id
        return variant == .upload ? "\(base)-upload" : "\(base)-print-4x6"
    }
}

/// Crown, chin and eye lines over the finished photo, with a mm scale.
struct MeasurementOverlay: View {
    let output: RenderedOutput
    let spec: DocumentSpec

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let pxHeight = Double(output.digital.height)
            let geo = SpecGeometry(spec: spec)
            let headMM = geo.map { $0.pxToMM(Double(output.headHeightPx)) } ?? 0

            ZStack(alignment: .topLeading) {
                line(at: crownFraction, in: size, label: "crown")
                line(at: chinFraction, in: size, label: "chin")
                Text(String(format: "head %.1f mm", headMM))
                    .font(.caption2.bold())
                    .padding(4)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
                    .position(x: size.width - 48, y: size.height * (crownFraction + chinFraction) / 2)
            }
            .allowsHitTesting(false)
            .onAppear { _ = pxHeight }
        }
    }

    // Crown and chin are measured in the crop, so express them as fractions of the output.
    private var crownFraction: Double {
        guard let geo = SpecGeometry(spec: spec) else { return 0 }
        let topMM = spec.geometry.topMargin?.targetMM ?? 2.2
        return topMM / spec.photo.sizeMM.height * (geo.outputSizePx.height / geo.outputSizePx.height)
    }

    private var chinFraction: Double {
        guard let geo = SpecGeometry(spec: spec) else { return 0 }
        let topMM = spec.geometry.topMargin?.targetMM ?? 2.2
        let headMM = geo.pxToMM(Double(output.headHeightPx))
        return (topMM + headMM) / spec.photo.sizeMM.height
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
