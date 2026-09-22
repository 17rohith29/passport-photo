import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import Observation
import PhotoAnalysis
import PhotoPipeline
import SpecKit
import UIKit

/// Runs the camera and coaches the person through a usable shot.
///
/// The advice itself is `CaptureGuidance`, which is pure and lives in PassportKit. This class
/// only owns AVFoundation, the frame throttle and the spoken cues.
@MainActor
@Observable
final class CameraController: NSObject {

    enum Status: Equatable {
        case idle
        case denied
        case unavailable(String)
        case running
    }

    private(set) var status: Status = .idle
    private(set) var assessment: CaptureAssessment?
    private(set) var readiness: Double = 0
    private(set) var capturedData: Data?
    var usingFrontCamera = false
    var autoCapture = true
    var speaksCues = true

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "camera.frames")
    private let analyzer = VisionFaceAnalyzer()
    /// Created once: a CIContext per frame is expensive.
    private nonisolated let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let speaker = AVSpeechSynthesizer()

    private var spec: DocumentSpec?
    private var stabiliser = CaptureStabiliser()
    private var analysing = false
    private var lastAnalysis = Date.distantPast
    private var lastSpoken: CaptureCue.Kind?
    private var lastSpokenAt = Date.distantPast

    /// Vision on every frame would heat the phone and drop the preview; five a second is enough
    /// for someone adjusting their position.
    private let analysisInterval: TimeInterval = 0.2

    func start(spec: DocumentSpec) async {
        self.spec = spec
        guard await requestAccess() else { status = .denied; return }
        guard configure() else { return }
        await withCheckedContinuation { continuation in
            queue.async { [session] in
                if !session.isRunning { session.startRunning() }
                continuation.resume()
            }
        }
        status = .running
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
        speaker.stopSpeaking(at: .immediate)
        stabiliser.reset()
        readiness = 0
    }

    func flipCamera() {
        usingFrontCamera.toggle()
        stabiliser.reset()
        readiness = 0
        _ = configure()
    }

    func clearCapture() { capturedData = nil }

    private func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    private func configure() -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.inputs.forEach { session.removeInput($0) }
        session.sessionPreset = .photo

        // The rear camera is sharper and has no wide-angle distortion, which is why the tips ask
        // for a friend or a tripod. The front camera stays available because it is what most
        // people have to hand.
        let position: AVCaptureDevice.Position = usingFrontCamera ? .front : .back
        let types: [AVCaptureDevice.DeviceType] = usingFrontCamera
            ? [.builtInWideAngleCamera]
            : [.builtInDualCamera, .builtInWideAngleCamera]
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: types, mediaType: .video, position: position
        )
        guard let device = discovery.devices.first,
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input)
        else {
            status = .unavailable("No camera is available on this device.")
            return false
        }
        session.addInput(input)

        if session.outputs.isEmpty {
            guard session.canAddOutput(photoOutput), session.canAddOutput(videoOutput) else {
                status = .unavailable("The camera could not be set up.")
                return false
            }
            session.addOutput(photoOutput)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: queue)
            session.addOutput(videoOutput)
        }
        orient(photoOutput.connection(with: .video))
        orient(videoOutput.connection(with: .video))
        return true
    }

    /// Portrait, and never mirrored.
    ///
    /// The preview layer mirrors the front camera on its own, which is what people expect to see.
    /// The frames Vision measures must NOT be mirrored, or the face would be reported on the wrong
    /// side; `CaptureGuidance` is told separately that the preview is a mirror so it can reverse
    /// the instruction. The captured photo must not be mirrored either — a flipped passport photo
    /// is a wrong passport photo.
    private func orient(_ connection: AVCaptureConnection?) {
        guard let connection else { return }
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
    }

    func capture() {
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .quality
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    /// Whether this frame should be analysed at all. Checked on the main actor before the
    /// capture queue does any conversion work.
    fileprivate func shouldAnalyse() -> Bool {
        let now = Date()
        guard !analysing, now.timeIntervalSince(lastAnalysis) >= analysisInterval, spec != nil
        else { return false }
        analysing = true
        lastAnalysis = now
        return true
    }

    fileprivate func analyse(_ frame: Frame) {
        guard let spec else { analysing = false; return }
        let mirrored = usingFrontCamera
        Task { [weak self] in
            guard let self else { return }
            let image = frame.image
            let face = try? await self.analyzer.analyze(image)
            let result = CaptureGuidance.assess(
                face: face, headHeightPx: nil, cheekImbalance: nil,
                frameSize: CGSize(width: image.width, height: image.height),
                spec: spec, isMirrored: mirrored
            )
            self.apply(result)
            self.analysing = false
        }
    }

    /// A decoded frame on its way to the main actor.
    ///
    /// `CGImage` is immutable once created and is handed over exclusively, so carrying it across
    /// the actor boundary is safe. The conversion happens synchronously in the capture callback
    /// because the `CVPixelBuffer` behind it is recycled as soon as that callback returns.
    fileprivate struct Frame: @unchecked Sendable {
        let image: CGImage
    }

    private func apply(_ result: CaptureAssessment) {
        assessment = result
        let fired = stabiliser.update(isReady: result.isReady)
        readiness = stabiliser.progress
        speak(result.primary)
        if fired, autoCapture, capturedData == nil {
            Haptics.success()
            capture()
        }
    }

    /// Speaks the top cue, and does not repeat itself until it changes or three seconds pass.
    private func speak(_ cue: CaptureCue?) {
        guard speaksCues, let cue, cue.kind != .ready else { return }
        let now = Date()
        guard cue.kind != lastSpoken || now.timeIntervalSince(lastSpokenAt) > 3 else { return }
        lastSpoken = cue.kind
        lastSpokenAt = now
        let utterance = AVSpeechUtterance(string: cue.message)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        speaker.speak(utterance)
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard width > 0, height > 0 else { return }

        // Converted here, on the capture queue, while the buffer is still valid.
        guard let image = ciContext.createCGImage(
            CIImage(cvPixelBuffer: buffer),
            from: CGRect(x: 0, y: 0, width: width, height: height)
        ) else { return }
        let frame = Frame(image: image)

        Task { @MainActor [weak self] in
            guard let self, self.shouldAnalyse() else { return }
            self.analyse(frame)
        }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard let data = photo.fileDataRepresentation() else { return }
        Task { @MainActor [weak self] in
            self?.capturedData = data
            self?.stop()
        }
    }
}
