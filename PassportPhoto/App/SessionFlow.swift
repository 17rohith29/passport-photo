import PhotoPipeline
import SpecKit
import SwiftUI

/// Processing → rejection or result, over the imported photo.
struct SessionFlow: View {
    @Bindable var session: PhotoSessionModel
    let spec: DocumentSpec

    var body: some View {
        NavigationStack {
            Group {
                switch session.stage {
                case .idle, .working:
                    ProcessingView(session: session)
                case .rejected:
                    RejectionView(session: session, spec: spec)
                case .finished:
                    ResultView(session: session, spec: spec)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(session.isWorking ? "Cancel" : "Done") {
                        session.cancel()
                        session.reset()
                    }
                }
            }
        }
    }
}

struct ProcessingView: View {
    let session: PhotoSessionModel

    private static let steps = [
        "Reading your photo",
        "Checking quality and finding your face",
        "Removing the background",
        "Cropping to size",
        "Verifying the result",
    ]

    var body: some View {
        VStack(spacing: 28) {
            if let image = session.sourceImage {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 280)
                    .opacity(0.35)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // No fake progress bar: the current step is the only honest signal.
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Self.steps, id: \.self) { step in
                    HStack(spacing: 10) {
                        Image(systemName: icon(for: step))
                            .foregroundStyle(isCurrent(step) ? Color.accentColor : .secondary)
                        Text(step)
                            .foregroundStyle(isCurrent(step) ? .primary : .secondary)
                        Spacer()
                    }
                }
            }
            .padding()
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))

            ProgressView()
            Spacer()
        }
        .padding()
        .navigationTitle("Working")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var currentStep: String? {
        if case let .working(step) = session.stage { return step }
        return nil
    }

    private func isCurrent(_ step: String) -> Bool { currentStep == step }

    private func icon(for step: String) -> String {
        isCurrent(step) ? "circle.dotted" : "circle"
    }
}

struct RejectionView: View {
    let session: PhotoSessionModel
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

                if let error = session.loadError {
                    Text(error).foregroundStyle(.secondary)
                }

                ForEach(session.failures) { check in
                    CheckRow(check: check, emphasised: true)
                }

                let warnings = session.warnings
                if !warnings.isEmpty {
                    Text("Also worth fixing").font(.headline).padding(.top, 8)
                    ForEach(warnings) { check in CheckRow(check: check, emphasised: false) }
                }

                Button("Choose Another Photo") { session.reset() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .padding(.top)

                TipsSection()
            }
            .padding()
        }
        .navigationTitle("Can't use this photo")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headline: String {
        guard let first = session.failures.first else { return "This photo can't be used." }
        switch first.id {
        case .lighting: return "Your face is lit unevenly"
        case .resolution: return "You're too far from the camera"
        case .sharpness: return "The photo is blurry"
        case .mouthClosed: return "Your mouth is open"
        case .eyesOpen: return "Your eyes look closed"
        case .yaw, .pitch, .roll: return "Your head isn't straight on"
        case .faceCount: return "We need exactly one face"
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
                if let message = check.userMessage {
                    Text(message).font(.subheadline).padding(.top, 2)
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
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
