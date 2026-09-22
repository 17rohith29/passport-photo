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
    @State private var showingCamera = false
    @State private var selectedSpec: DocumentSpec?
    @Environment(\.dynamicTypeSize) private var typeSize

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
            .navigationBarTitleDisplayMode(typeSize.isAccessibilitySize ? .inline : .large)
        }
    }

    @ViewBuilder
    private func content(spec: DocumentSpec) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // One card per bundled spec, per docs/PLAN.md. A segmented control truncated
                // "Schengen Area, Schengen visa" to "Schengen Area,..." at three entries.
                VStack(spacing: 10) {
                    ForEach(catalog.specs) { option in
                        DocumentCard(
                            spec: option,
                            isSelected: option.id == spec.id,
                            onSelect: { selectedSpec = option },
                            onShowRequirements: {
                                selectedSpec = option
                                showingRequirements = true
                            }
                        )
                    }
                }

                VStack(spacing: 12) {
                    PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                        Label("Choose Photo", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        showingCamera = true
                    } label: {
                        Label("Take a Photo", systemImage: "camera")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button("Import from Files") { showingFileImporter = true }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                }

                TipsSection()
            }
            .padding()
        }
        .sheet(isPresented: $showingRequirements) {
            RequirementsSheet(spec: spec)
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CaptureView(spec: spec) { data in
                session.process(data: data, spec: spec)
            }
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
            if let id = DebugAutoRun.specID(), let match = catalog.specs.first(where: { $0.id == id }) {
                selectedSpec = match
                showingRequirements = DebugAutoRun.showRequirements
            }
            if DebugAutoRun.opensCamera { showingCamera = true }
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

    /// `-selectSpec <id>` and `-showRequirements` drive the picker for screenshots.
    static func specID() -> String? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-selectSpec"), index + 1 < arguments.count
        else { return nil }
        return arguments[index + 1]
        #else
        return nil
        #endif
    }

    static var opensCamera: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-openCamera")
        #else
        return false
        #endif
    }

    static var showRequirements: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-showRequirements")
        #else
        return false
        #endif
    }
}

struct DocumentCard: View {
    let spec: DocumentSpec
    var isSelected: Bool = false
    var onSelect: () -> Void = {}
    var onShowRequirements: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At accessibility sizes a flag beside the text squeezes it into a column so narrow that
        // "Passport" hyphenates to "Pass-port". Stack instead, and give the text the full width.
        let stacked = typeSize.isAccessibilitySize

        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                if stacked {
                    label
                    summaryText
                } else {
                    HStack(spacing: 14) {
                        flagView
                        VStack(alignment: .leading, spacing: 3) {
                            label
                            summaryText
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: stacked ? .bottomTrailing : .trailing) {
            Button(action: onShowRequirements) {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Requirements for \(spec.country.name) \(spec.document.displayName)")
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var flagView: some View {
        Text(flag(for: spec.country.code))
            // Scales with Dynamic Type instead of staying a fixed 34 pt.
            .font(.system(size: 34))
            .accessibilityHidden(true)
    }

    private var label: some View {
        HStack(spacing: 8) {
            if typeSize.isAccessibilitySize { flagView.font(.title) }
            Text("\(spec.country.name), \(spec.document.displayName)")
                .font(.headline)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var summaryText: some View {
        Text(summary)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var summary: String {
        let size = "\(trim(spec.photo.sizeMM.width)) × \(trim(spec.photo.sizeMM.height)) mm"
        // The background colour is detail; at accessibility sizes the size alone is the point.
        guard !typeSize.isAccessibilitySize else { return size }
        switch spec.background?.colorHex.uppercased() {
        case "#FFFFFF": return "\(size), white background"
        case .none: return size
        default: return "\(size), light grey background"
        }
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
        "Ask someone to take it, or prop the phone on a shelf — the back camera is sharper than the selfie one.",
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
