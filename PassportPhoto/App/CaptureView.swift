import AVFoundation
import PhotoPipeline
import SpecKit
import SwiftUI

/// Live preview with a head guide and one instruction at a time.
struct CaptureView: View {
    let spec: DocumentSpec
    let onCaptured: (Data) -> Void

    @State private var camera = CameraController()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                switch camera.status {
                case .running:
                    preview
                case .denied:
                    message(
                        "Camera access is off",
                        "Turn it on in Settings to take a photo here, or import one instead.",
                        symbol: "camera.fill"
                    )
                case let .unavailable(text):
                    message("No camera", text, symbol: "camera.fill")
                case .idle:
                    ProgressView().tint(.white)
                }
            }
            .navigationTitle("Take the photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { camera.stop(); dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        camera.flipCamera()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                    }
                    .accessibilityLabel(camera.usingFrontCamera ? "Use the back camera" : "Use the front camera")
                }
            }
        }
        .task { await camera.start(spec: spec) }
        .onDisappear { camera.stop() }
        .onChange(of: camera.capturedData) { _, data in
            guard let data else { return }
            onCaptured(data)
            camera.clearCapture()
            dismiss()
        }
    }

    private var preview: some View {
        GeometryReader { geometry in
            ZStack {
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()

                HeadGuide(
                    band: camera.assessment?.targetHeadFraction ?? 0.5...0.6,
                    isReady: camera.assessment?.isReady ?? false
                )
                .ignoresSafeArea()

                VStack {
                    cueBanner
                        .padding(.top, 8)
                    Spacer()
                    controls
                }
                .padding()
            }
            .onAppear { _ = geometry }
        }
    }

    private var cueBanner: some View {
        let cue = camera.assessment?.primary
        return Text(cue?.message ?? "Looking for you…")
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                (cue?.kind == .ready ? Color.green : Color.black.opacity(0.55)),
                in: Capsule()
            )
            .animation(.easeInOut(duration: 0.15), value: cue?.kind)
            // VoiceOver users get the cue as a live announcement rather than a silent label.
            .accessibilityLabel(cue?.message ?? "Looking for you")
            .accessibilityAddTraits(.updatesFrequently)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            if camera.usingFrontCamera {
                Text("The back camera is sharper. Ask someone to hold the phone, or prop it up.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 28) {
                Toggle("Auto", isOn: $camera.autoCapture)
                    .toggleStyle(.button)
                    .tint(.white)
                    .accessibilityLabel("Take the photo automatically when everything is right")

                Button(action: { camera.capture() }) {
                    ZStack {
                        Circle().strokeBorder(.white, lineWidth: 4).frame(width: 74, height: 74)
                        Circle().fill(.white).frame(width: 60, height: 60)
                        Circle()
                            .trim(from: 0, to: camera.readiness)
                            .stroke(Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .frame(width: 74, height: 74)
                            .rotationEffect(.degrees(-90))
                    }
                }
                .accessibilityLabel("Take photo")

                Toggle("Voice", isOn: $camera.speaksCues)
                    .toggleStyle(.button)
                    .tint(.white)
                    .accessibilityLabel("Speak the instructions aloud")
            }
            .foregroundStyle(.white)
        }
        .padding(.bottom, 8)
    }

    private func message(_ title: String, _ detail: String, symbol: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(detail)
        }
        .foregroundStyle(.white)
    }
}

/// The oval the head should fill. Its height is the spec's target head fraction, so it means
/// something: fill it and the head is the right size for this document.
struct HeadGuide: View {
    let band: ClosedRange<Double>
    let isReady: Bool

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height * ((band.lowerBound + band.upperBound) / 2)
            let width = height * 0.72
            Ellipse()
                .strokeBorder(
                    isReady ? Color.green : Color.white.opacity(0.85),
                    style: StrokeStyle(lineWidth: 3, dash: isReady ? [] : [10, 8])
                )
                .frame(width: width, height: height)
                .position(x: geometry.size.width / 2, y: geometry.size.height * 0.42)
                .animation(.easeInOut(duration: 0.2), value: isReady)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
