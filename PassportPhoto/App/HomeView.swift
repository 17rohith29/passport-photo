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
    @State private var showingPicker = false
    @State private var showingPhotosPicker = false
    /// Held until the camera sheet has actually gone. Presenting the processing sheet while the
    /// capture sheet is still dismissing makes SwiftUI drop the second presentation, and the
    /// photo silently vanishes.
    @State private var pendingCapture: Data?
    @State private var selectedSpec: DocumentSpec?
    @State private var debugSaved: SaveOutcome?
    /// Set when the rejection screen asks for another photo, acted on once the cover has gone.
    @State private var wantsPicker = false
    @AppStorage("selectedDocumentID") private var storedDocumentID = ""
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            Group {
                if let spec = currentSpec {
                    content(spec: spec)
                } else {
                    ContentUnavailableView(
                        "No document specs",
                        systemImage: "doc.questionmark",
                        description: Text(catalog.loadFailures.first ?? "No spec JSON was bundled with the app.")
                    )
                }
            }
            .navigationTitle("Passport & Visa Photos")
            .navigationBarTitleDisplayMode(typeSize.isAccessibilitySize ? .inline : .large)
        }
    }

    /// The chosen document: whatever is selected now, else the one remembered from last time,
    /// else the first available.
    private var currentSpec: DocumentSpec? {
        selectedSpec ?? catalog.specs.first { $0.id == storedDocumentID } ?? localeSpec
    }

    /// The document determines every number downstream, so guessing it alphabetically - which
    /// started every new user in the world on Australia - is worse than guessing from where the
    /// phone says it is. When even that is unknown, nothing is preselected.
    private var localeSpec: DocumentSpec? {
        guard let region = Locale.current.region?.identifier else { return nil }
        return catalog.specs.first { $0.country.code == region }
    }

    /// True when we are showing a document the user never chose.
    private var isGuessedDocument: Bool {
        selectedSpec == nil && !catalog.specs.contains { $0.id == storedDocumentID }
    }

    private func select(_ spec: DocumentSpec) {
        selectedSpec = spec
        storedDocumentID = spec.id
    }

    @ViewBuilder
    private func content(spec: DocumentSpec) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // One card per document stopped scaling at eight: the list pushed Choose Photo
                // below the fold. The selected document is shown and the rest live behind a
                // searchable picker.
                VStack(alignment: .leading, spacing: 10) {
                    // A stranger is being asked to hand over a photo of their face. That this
                    // never leaves the phone is the strongest thing the app has, and it was
                    // nowhere in the UI.
                    Text("Turn a photo you already have into a passport or visa photo that meets the measurements. Everything happens on this iPhone — nothing is uploaded.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SelectedDocumentCard(
                    spec: spec,
                    otherCount: max(0, catalog.specs.count - 1),
                    isGuessed: isGuessedDocument,
                    onChange: { showingPicker = true },
                    onShowRequirements: { showingRequirements = true }
                )

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

                    // The frame has to go on the label, as it does on the two above: applied
                    // to the button it widens the frame while the capsule hugs its text.
                    Button { showingFileImporter = true } label: {
                        Text("Import from Files")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                TipsSection()

                Text("No account, no internet, no uploads.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
            .padding()
        }
        .sheet(isPresented: $showingRequirements) {
            RequirementsSheet(spec: spec)
        }
        .sheet(item: $debugSaved) { outcome in
            SavedView(spec: spec, outcome: outcome) { debugSaved = nil }
        }
        .sheet(isPresented: $showingPicker) {
            DocumentPickerSheet(
                specs: catalog.specs,
                selectedID: spec.id,
                onSelect: { select($0) }
            )
        }
        .fullScreenCover(isPresented: $showingCamera, onDismiss: {
            if let data = pendingCapture {
                pendingCapture = nil
                session.process(data: data, spec: spec)
            }
        }) {
            CaptureView(spec: spec) { data in pendingCapture = data }
        }
        .fullScreenCover(isPresented: Binding(
            get: { session.phase != .idle },
            set: { if !$0 { session.reset(); saver.reset() } }
        ), onDismiss: {
            if wantsPicker {
                wantsPicker = false
                showingPhotosPicker = true
            }
        }) {
            SessionFlow(session: session, saver: saver, spec: spec) { wantsPicker = true }
        }
        .photosPicker(isPresented: $showingPhotosPicker, selection: $pickerItem, matching: .images)
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
                select(match)
                showingRequirements = DebugAutoRun.showRequirements
            }
            if let variant = DebugAutoRun.savedVariant() {
                debugSaved = SaveOutcome(destination: .photos, variant: variant)
            }
            if DebugAutoRun.opensPicker { showingPicker = true }
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

    static var opensPicker: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-openPicker")
        #else
        return false
        #endif
    }

    static var opensCamera: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-openCamera")
        #else
        return false
        #endif
    }

    /// `-showSaved single|sheet` opens the end screen directly. Vision does not run in the
    /// simulator, so this is the only way to see it there.
    static func savedVariant() -> PrintGuidance.Variant? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-showSaved"), index + 1 < arguments.count
        else { return nil }
        return PrintGuidance.Variant(rawValue: arguments[index + 1])
        #else
        return nil
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

/// The document in use, and the way to change it.
struct SelectedDocumentCard: View {
    let spec: DocumentSpec
    let otherCount: Int
    /// True when this is our guess rather than the user's choice, so we say so.
    var isGuessed = false
    let onChange: () -> Void
    let onShowRequirements: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onChange) {
                HStack(spacing: 14) {
                    Text(DocumentStyle.flag(for: spec.country.code))
                        .font(.system(size: 34))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(spec.country.name), \(spec.document.displayName)")
                            .font(.headline)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        // At accessibility sizes the summary costs four lines and pushes the
                        // primary action off screen; the flag is one glyph and identifies the
                        // document instantly, so it is the summary that goes.
                        if !typeSize.isAccessibilitySize {
                            Text(DocumentStyle.summary(for: spec))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if isGuessed {
                            Text("Our guess — tap to change")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(spec.country.name), \(spec.document.displayName). \(DocumentStyle.summary(for: spec))")
            .accessibilityHint(otherCount > 0 ? "Change document. \(otherCount) others available" : "Change document")

            Divider()

            Button(action: onShowRequirements) {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text("Requirements")
                    Spacer(minLength: 0)
                }
                .font(.subheadline)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Requirements for \(spec.country.name) \(spec.document.displayName)")
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
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
