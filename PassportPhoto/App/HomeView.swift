import PhotoPipeline
import PhotosUI
import SpecKit
import SwiftUI

struct HomeView: View {
    @State private var catalog = SpecCatalog()
    @State private var session = PhotoSession()
    @State private var saver = PhotoSaver()
    @State private var pickerItem: PhotosPickerItem?
    @State private var showingRequirements = false
    @State private var showingFileImporter = false
    @State private var selectedSpec: DocumentSpec?

    var body: some View {
        NavigationStack {
            Group {
                if let spec = selectedSpec ?? catalog.specs.first {
                    content(spec: spec)
                } else {
                    ContentUnavailableView(
                        "No document specs",
                        systemImage: "doc.questionmark",
                        description: Text(catalog.loadFailures.first ?? "No spec JSON was bundled with the app.")
                    )
                }
            }
            .navigationTitle("Passport Photo")
        }
    }

    @ViewBuilder
    private func content(spec: DocumentSpec) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DocumentCard(spec: spec) { showingRequirements = true }

                VStack(spacing: 12) {
                    PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                        Label("Choose Photo", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Import from Files") { showingFileImporter = true }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                }

                if catalog.specs.count > 1 {
                    Picker("Document", selection: Binding(
                        get: { (selectedSpec ?? spec).id },
                        set: { id in selectedSpec = catalog.specs.first { $0.id == id } }
                    )) {
                        ForEach(catalog.specs) { option in
                            Text("\(option.country.name), \(option.document.displayName)").tag(option.id)
                        }
                    }
                    .pickerStyle(.segmented)
                } else {
                    Text("More countries coming")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                TipsSection()
            }
            .padding()
        }
        .sheet(isPresented: $showingRequirements) {
            RequirementsSheet(spec: spec)
        }
        .fullScreenCover(isPresented: Binding(
            get: { session.phase != .idle },
            set: { if !$0 { session.reset(); saver.reset() } }
        )) {
            SessionFlow(session: session, saver: saver, spec: spec)
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    session.process(data: data, spec: spec)
                }
                pickerItem = nil
            }
        }
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.image]) { result in
            guard case let .success(url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                session.process(data: data, spec: spec)
            }
        }
        .task {
            // Lets the flow be driven without tapping, for screenshotting the real screens.
            if let data = DebugAutoRun.photoData() {
                session.process(data: data, spec: spec)
            }
        }
    }
}

/// Debug builds only: `-autoProcessPhoto <path>` runs that file through the flow on launch.
enum DebugAutoRun {
    static func photoData() -> Data? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-autoProcessPhoto"),
              index + 1 < arguments.count else { return nil }
        return try? Data(contentsOf: URL(fileURLWithPath: arguments[index + 1]))
        #else
        return nil
        #endif
    }
}

struct DocumentCard: View {
    let spec: DocumentSpec
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Text(flag(for: spec.country.code))
                    .font(.system(size: 40))
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(spec.country.name), \(spec.document.displayName)")
                        .font(.headline)
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the full requirements")
    }

    private var summary: String {
        let size = "\(trim(spec.photo.sizeMM.width)) × \(trim(spec.photo.sizeMM.height)) mm"
        let background = spec.background?.colorHex == "#FFFFFF" ? "white background" : "coloured background"
        return "\(size), \(background)"
    }

    private func trim(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%g", value)
    }

    /// Regional indicator symbols from the ISO country code.
    private func flag(for code: String) -> String {
        let base: UInt32 = 127397
        var result = ""
        for scalar in code.unicodeScalars {
            if let value = UnicodeScalar(base + scalar.value) { result.unicodeScalars.append(value) }
        }
        return result.isEmpty ? "🏳️" : result
    }
}

struct TipsSection: View {
    var body: some View {
        DisclosureGroup("Tips for a photo that works") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Self.tips, id: \.self) { tip in
                    Label(tip, systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .labelStyle(.titleAndIcon)
                }
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }

    static let tips = [
        "Face a window so the light is even on both cheeks.",
        "Stand in front of a plain, light wall.",
        "Hold the phone at eye level, about 1.5 m away.",
        "Use the rear camera with the 2x lens.",
        "Neutral expression, mouth closed, no glasses.",
    ]
}

#Preview {
    HomeView()
}
