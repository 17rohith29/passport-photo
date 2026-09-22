import PhotoPipeline
import SpecKit
import SwiftUI

/// Processing → rejection or result, over the imported photo.
struct SessionFlow: View {
    let session: PhotoSession
    let saver: PhotoSaver
    let spec: DocumentSpec

    var body: some View {
        NavigationStack {
            Group {
                switch session.phase {
                case .idle, .working:
                    ProcessingView(session: session)
                case .rejected:
                    RejectionView(session: session, spec: spec)
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
                    Button(session.isWorking ? "Cancel" : "Done") {
                        session.reset()
                        saver.reset()
                    }
                }
            }
        }
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
    let session: PhotoSession
    let spec: DocumentSpec

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let image = session.sourceImage {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .frame(maxWidth: .infinity)
                }

                Text(headline)
                    .font(.title2.bold())

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
                Button(session.isDeviceLimitation ? "Back" : "Choose Another Photo") {
                    session.reset()
                }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .padding(.top)

                if !session.isDeviceLimitation { TipsSection() }
            }
            .padding()
        }
        .navigationTitle(session.isDeviceLimitation ? "Can't process here" : "Can't use this photo")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headline: String {
        if session.isDeviceLimitation { return "This device can't process photos" }
        guard let first = session.failures.first else {
            return session.failureReason == nil
                ? "This photo can't be used."
                : "Something went wrong processing this photo"
        }
        switch first.id {
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
