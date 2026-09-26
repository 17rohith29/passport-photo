import PhotoPipeline
import SpecKit
import SwiftUI

/// Processing → rejection or result, over the imported photo.
struct SessionFlow: View {
    let session: PhotoSession
    let saver: PhotoSaver
    let spec: DocumentSpec
    /// Home owns the photo picker, so "Choose Another Photo" has to ask it to re-present.
    var onChooseAnother: () -> Void = {}

    var body: some View {
        NavigationStack {
            Group {
                switch session.phase {
                case .idle, .working:
                    ProcessingView(session: session)
                case .rejected:
                    RejectionView(session: session, spec: spec, onChooseAnother: onChooseAnother)
                case .finished:
                    ResultView(session: session, saver: saver, spec: spec)
                }
            }
            // These screens are presented in a fullScreenCover, and a VStack or ScrollView only
            // sizes to its content — so without an explicit opaque background the Home screen
            // showed straight through and the cover looked like an overlay rather than a screen.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .onChange(of: session.phase) { _, phase in
                switch phase {
                case .finished: Haptics.forVerdict(session.result?.verdict ?? .meetsRequirements)
                case .rejected: Haptics.failure()
                default: break
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(toolbarLabel) {
                        session.reset()
                        saver.reset()
                    }
                }
            }
        }
    }
}

extension SessionFlow {
    var toolbarLabel: String {
        if session.isWorking { return "Cancel" }
        return session.phase == .rejected ? "Close" : "Done"
    }
}

struct ProcessingView: View {
    let session: PhotoSession
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 28) {
            if let image = session.sourceImage, !typeSize.isAccessibilitySize {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 280)
                    .opacity(0.35)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
            }

            // No fake progress bar: the real stage the pipeline reports is the only honest signal.
            VStack(alignment: .leading, spacing: 12) {
                ForEach(PipelineStage.allCases, id: \.self) { step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        icon(for: step)
                            .frame(width: 20)
                        Text(step.rawValue)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(isCurrent(step) || isDone(step) ? .primary : .secondary)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(accessibilityLabel(for: step))
                }
            }
            .padding()
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
            .animation(.default, value: session.completed)

            Spacer()
        }
        .padding()
        .navigationTitle("Working")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func isCurrent(_ step: PipelineStage) -> Bool { session.currentStage == step }
    private func isDone(_ step: PipelineStage) -> Bool { session.completed.contains(step) }

    @ViewBuilder
    private func icon(for step: PipelineStage) -> some View {
        if isDone(step) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else if isCurrent(step) {
            ProgressView().controlSize(.small)
        } else {
            Image(systemName: "circle").foregroundStyle(.tertiary)
        }
    }

    private func accessibilityLabel(for step: PipelineStage) -> String {
        if isDone(step) { return "\(step.rawValue), done" }
        if isCurrent(step) { return "\(step.rawValue), in progress" }
        return "\(step.rawValue), waiting"
    }
}

struct RejectionView: View {
    @AppStorage("keepBackground") private var keepBackground = false
    let session: PhotoSession
    let spec: DocumentSpec
    var onChooseAnother: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // When the photo was rendered but failed its own measurements, showing the
                // result is more honest than hiding it: "we made this, and here is why it does
                // not measure up". What we must never do is put a Save button under it.
                if let rendered = session.output?.digital {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(decorative: rendered, scale: 1)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .padding(8)
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                            .frame(maxWidth: .infinity)
                        Text("This is what we produced. It does not meet the measurements below, so it is not offered for saving.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else if let image = session.sourceImage {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .frame(maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(headline)
                        .font(.title2.bold())
                    // The headline names one failure; the list below may hold three. Say how
                    // many before the user starts scrolling.
                    if session.failures.count > 1 {
                        Text("\(session.failures.count) things to fix before you retake.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if session.failures.isEmpty, let reason = session.failureReason {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(reason)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let detail = session.technicalDetail {
                            DisclosureGroup("Technical detail") {
                                Text(detail)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(.caption)
                        }
                    }
                }

                ForEach(session.failures) { check in
                    CheckRow(check: check, emphasised: true)
                }

                let warnings = session.warnings
                if !warnings.isEmpty {
                    Text("Also worth fixing").font(.headline).padding(.top, 8)
                    ForEach(warnings) { check in CheckRow(check: check, emphasised: false) }
                }

                // No point offering another photo when no photo would work here.
                // Keeping the user's own wall is what failed, so offer the edit rather than
                // leaving them with only "choose another photo". The country's own warning is
                // attached, because for these documents the edit is the risky option.
                if keptWallFailed {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("We kept your own background because \(spec.country.name) does not accept an edited photo, and your wall is not white enough to pass on its own.")
                            .font(.subheadline)
                        // NOT spec.editingRisk: that is written in the past tense for the path
                        // where we replaced the background, and would tell the user we replaced
                        // a background we had just kept.
                        Text("Replacing it would meet the measurements, but \(spec.country.name) rules out a photo altered with software — so a replaced background may not be accepted either.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            // They have now told us their wall cannot pass. Putting the next
                            // photo through the same failure would be the app not listening.
                            keepBackground = false
                            session.reprocess(mode: .replace)
                        } label: {
                            Text("Replace the background anyway")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        // Prominent here: another photo from the same room has the same wall,
                        // so this is the button that actually helps.
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
                }

                // Nothing else to try when no photo would work here: the toolbar's Close is
                // the only action, so a second button offering the same destination is noise.
                if !session.isDeviceLimitation {
                    // The frame goes on the label. Applied to the button it widens the hit frame
                    // while the capsule hugs its text, which left the one recovery action on the
                    // worst screen looking demoted.
                    let label = Text("Choose Another Photo")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    let action: () -> Void = {
                        session.reset()
                        // The button named an action and performed a dismissal: it dropped the
                        // user on Home to find "Choose Photo" themselves, at the moment they
                        // are most likely to give up.
                        onChooseAnother()
                    }
                    // When the wall is what failed, another photo from the same room has the
                    // same wall — so "Replace the background anyway" above is the real recovery
                    // and gets the prominence.
                    if keptWallFailed {
                        Button(action: action) { label }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .padding(.top)
                    } else {
                        Button(action: action) { label }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .padding(.top)
                    }
                }

                if !session.isDeviceLimitation { TipsSection() }
            }
            .padding()
        }
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var navigationTitleText: String {
        if session.isDeviceLimitation { return "Couldn't analyse this" }
        return keptWallFailed ? "One thing to fix" : "Can't use this photo"
    }

    /// Keeping the user's wall is what failed, and replacing it is the way out.
    private var keptWallFailed: Bool {
        // Only when the wall is the ONLY thing wrong. Offering "replace the background" against
        // three other failures leads straight to a second rejection, and announcing "one thing
        // to fix" above a list of three is worse than saying nothing.
        session.backgroundMode == .keep
            && session.failures.count == 1
            && session.failures.first?.id == .background
    }

    private var headline: String {
        // True in the Simulator, false and insulting on a real iPhone.
        if session.isDeviceLimitation {
            #if targetEnvironment(simulator)
            return "This device can't process photos"
            #else
            return "Photo analysis didn't start"
            #endif
        }
        guard let first = session.failures.first else {
            return session.failureReason == nil
                ? "This photo can't be used."
                : "Something went wrong processing this photo"
        }
        // The wall failing is not "this photo can't be used" - the photo is fine, the room is
        // the problem, and saying it twice (nav title and headline) reads as a broken app.
        if keptWallFailed { return "The wall behind you isn't white enough" }

        switch first.id {
        case .colour: return "This photo is black and white"
        case .lighting: return "Your face is lit unevenly"
        case .resolution: return "You're too far from the camera"
        case .sharpness: return "The photo is blurry"
        case .mouthClosed: return "Your mouth is open"
        case .eyesOpen: return "Your eyes look closed"
        case .yaw, .pitch, .roll: return "Your head isn't straight on"
        case .faceCount: return "We need exactly one face"
        case .headroom: return "The top of your head is cut off"
        default: return "This photo can't be used"
        }
    }
}

struct CheckRow: View {
    let check: CheckResult
    var emphasised: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(colour)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(emphasised ? .headline : .subheadline)
                Text("Measured \(check.measured) · needs \(check.requirement)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let message = check.userMessage {
                    Text(message)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        let verdict: String
        switch check.status {
        case .pass: verdict = "passed"
        case .warn: verdict = "warning"
        case .fail: verdict = "failed"
        }
        var text = "\(title), \(verdict). Measured \(check.measured). Needs \(check.requirement)."
        if let message = check.userMessage { text += " \(message)" }
        return text
    }

    private var title: String {
        switch check.id {
        case .faceCount: return "Face"
        case .resolution: return "Distance and detail"
        case .sharpness: return "Sharpness"
        case .lighting: return "Even lighting"
        case .yaw: return "Facing the camera"
        case .pitch: return "Chin level"
        case .roll: return "Head straight"
        case .eyesOpen: return "Eyes open"
        case .mouthClosed: return "Mouth closed"
        case .dimensions: return "Photo size"
        case .fileSize: return "File size"
        case .headHeight: return "Head height"
        case .topMargin: return "Space above the head"
        case .headroom: return "Top of head visible"
        case .eyeLine: return "Eye position"
        case .centering: return "Centred"
        case .background: return "Background"
        case .faceIntegrity: return "Face untouched"
        case .colour: return "Colour photo"
        case .shouldersVisible: return "Shoulders visible"
        }
    }

    private var symbol: String {
        switch check.status {
        case .pass: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.circle.fill"
        }
    }

    private var colour: Color {
        switch check.status {
        case .pass: return .green
        case .warn: return .orange
        case .fail: return .red
        }
    }
}
