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
    private(set) var captureError: String?
    private(set) var isCapturing = false
    var usingFrontCamera = false
    var autoCapture = true
    /// Off by default: people take passport photos in offices and libraries, and a phone that
    /// starts talking unasked is worse than one that stays quiet. VoiceOver users get it on.
    var speaksCues = UIAccessibility.isVoiceOverRunning

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
    private var stopped = false
    private var lastAnalysis = Date.distantPast
    private var lastSpoken: CaptureCue.Kind?
    private var lastSpokenAt = Date.distantPast
    private var audioSessionActive = false

    /// Vision on every frame would heat the phone and drop the preview; five a second is enough
    /// for someone adjusting their position.
    nonisolated private let analysisInterval: TimeInterval = 0.2
    /// Frame-rate throttle, owned by the capture queue so it can run before any conversion work.
    nonisolated private let throttle = FrameThrottle()

    func start(spec: DocumentSpec) async {
        self.spec = spec
        stopped = false
        guard await requestAccess() else { status = .denied; return }
        // Cancelling during the permission prompt used to start the session anyway, leaving the
        // camera running behind a dismissed screen.
        guard !stopped, !Task.isCancelled else { return }
        guard configure() else { return }
        guard !stopped, !Task.isCancelled else { return }

        await withCheckedContinuation { continuation in
            queue.async { [session] in
                if !session.isRunning { session.startRunning() }
                continuation.resume()
            }
        }
        guard !stopped, !Task.isCancelled else {
            queue.async { [session] in if session.isRunning { session.stopRunning() } }
            return
        }
        status = .running
    }

    func stop() {
        stopped = true
        isCapturing = false
        status = .idle
        queue.async { [session, videoOutput] in
            // Detach first, or conversions keep running until the async stop lands.
            videoOutput.setSampleBufferDelegate(nil, queue: nil)
            if session.isRunning { session.stopRunning() }
        }
        speaker.stopSpeaking(at: .immediate)
        deactivateAudioSession()
        stabiliser.reset()
        readiness = 0
    }

    func flipCamera() {
        guard !isCapturing else { return }
        let previous = usingFrontCamera
        usingFrontCamera.toggle()
        stabiliser.reset()
        readiness = 0
        if configure() {
            status = .running
            return
        }
        // configure() removes the existing input before it knows the new device can be had, so
        // a failure leaves the session input-less. Put the old camera back rather than stranding
        // the screen on "No camera" with no way out.
        usingFrontCamera = previous
        if configure() {
            status = .running
        }
    }

    /// iOS stops the session when the app is backgrounded, when a call arrives, or when another
    /// app takes the camera. Nothing put it back: `status` stayed `.running`, so the view kept a
    /// live shutter over a frozen frame, and tapping it called `capturePhoto` on a stopped
    /// session - an Objective-C exception Swift cannot catch.
    func resumeIfNeeded() async {
        guard !stopped, let spec else { return }
        let running = await withCheckedContinuation { continuation in
            queue.async { [session] in continuation.resume(returning: session.isRunning) }
        }
        guard !running else { return }
        status = .idle
        stabiliser.reset()
        readiness = 0
        throttle.reset()
        await start(spec: spec)
    }

    func clearCapture() { capturedData = nil }
    func clearError() { captureError = nil }

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
            // Must be raised on the OUTPUT before any request asks for .quality. It defaults to
            // .balanced, and capturing with a higher prioritisation than the output allows raises
            // an Objective-C exception that Swift cannot catch, it crashed the app on the first
            // shutter press, which is also why auto-capture appeared to break everything.
            photoOutput.maxPhotoQualityPrioritization = .quality
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
    /// the instruction. The captured photo must not be mirrored either, a flipped passport photo
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
        guard status == .running, !isCapturing, captureError == nil else { return }
        isCapturing = true

        let settings = AVCapturePhotoSettings()
        // Clamped defensively as well: never ask for more than this output allows.
        let ceiling = photoOutput.maxPhotoQualityPrioritization
        settings.photoQualityPrioritization =
            ceiling.rawValue < AVCapturePhotoOutput.QualityPrioritization.quality.rawValue
            ? ceiling : .quality
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    fileprivate func finishCapture(_ data: Data?, error: Error?) {
        isCapturing = false
        stabiliser.reset()
        readiness = 0

        if let data {
            capturedData = data
            stop()
            return
        }
        // A failed capture used to return silently, leaving the shutter dead with nothing said.
        captureError = error?.localizedDescription ?? "The photo could not be taken. Try again."
        Haptics.failure()
    }

    /// Whether this frame should be analysed at all. Checked on the main actor before the
    /// capture queue does any conversion work.
    fileprivate func shouldAnalyse() -> Bool {
        guard !analysing, spec != nil else { return false }
        analysing = true
        lastAnalysis = Date()
        return true
    }

    fileprivate func analyse(_ frame: Frame) {
        guard let spec else { analysing = false; return }
        let mirrored = usingFrontCamera
        Task { [weak self] in
            guard let self else { return }
            let image = frame.image
            let face = try? await self.analyzer.analyze(image)
            // Background and lighting, judged on a small copy of the frame: a person can still
            // move at this point, which they cannot once the photo has been taken.
            let quality = face.flatMap { Self.quality(of: image, face: $0) }
            let result = CaptureGuidance.assess(
                face: face, headHeightPx: nil, cheekImbalance: nil, quality: quality,
                frameSize: CGSize(width: image.width, height: image.height),
                spec: spec, isMirrored: mirrored
            )
            self.apply(result)
            self.analysing = false
        }
    }

    /// Measured on a downscaled copy: the metrics are regional averages, so the detail a full
    /// frame carries is wasted, and this runs several times a second on a live preview.
    nonisolated static func quality(
        of image: CGImage, face: FaceMeasurements
    ) -> FrameQuality.Reading? {
        let side = 384
        let scale = Double(side) / Double(max(image.width, image.height))
        guard scale > 0, scale <= 1,
              let small = ImageLoader.resized(image, scale: scale),
              let pixels = ImageConversion.pixelImage(from: small) else { return nil }
        let luminance = ImageConversion.luminance(of: pixels)
        return FrameQuality.assess(
            image: pixels, luminance: luminance, face: face.scaled(by: scale)
        )
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
        // captureError: the failure alert is up and the user is being asked to decide.
        if fired, autoCapture, capturedData == nil, !isCapturing, captureError == nil {
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
        activateAudioSession()
        let utterance = AVSpeechUtterance(string: cue.message)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        speaker.speak(utterance)
    }

    /// AVSpeechSynthesizer plays through the app's audio session, and an app that never
    /// configures one gets .soloAmbient, which the Ring/Silent switch mutes outright. A phone on
    /// silent is the normal state for someone standing in an office or a library, which is
    /// exactly where this toggle gets turned on, so the cues were inaudible in the case they
    /// exist for. Nothing was wrong with the speech itself, which is why it looked like a dead
    /// feature rather than a muted one.
    ///
    /// .playback is heard regardless of the switch. Ducking rather than interrupting leaves
    /// whatever they were listening to playing underneath, and .voicePrompt is the mode built
    /// for spoken guidance of this kind.
    private func activateAudioSession() {
        guard !audioSessionActive else { return }
        let audio = AVAudioSession.sharedInstance()
        do {
            try audio.setCategory(.playback, mode: .voicePrompt,
                                  options: [.duckOthers, .mixWithOthers])
            try audio.setActive(true)
            audioSessionActive = true
        } catch {
            // A cue that cannot be spoken is not worth failing a capture over. The same words
            // are already on screen, which is the primary channel either way.
        }
    }

    private func deactivateAudioSession() {
        guard audioSessionActive else { return }
        audioSessionActive = false
        try? AVAudioSession.sharedInstance().setActive(
            false, options: [.notifyOthersOnDeactivation])
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

        // The throttle has to come BEFORE the conversion. It used to sit after it, so a full
        // frame was rendered by CIContext ~30 times a second and ~25 of those were thrown away
        // - sustained GPU load, thermal throttling and a stuttering preview, on the one screen
        // whose job is holding still.
        guard throttle.allows(interval: analysisInterval) else { return }

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
        let data = photo.fileDataRepresentation()
        Task { @MainActor [weak self] in
            self?.finishCapture(data, error: error)
        }
    }
}


/// Rate limiter for the capture queue. Lives outside the main actor so a frame can be discarded
/// before any conversion work is done on it.
final class FrameThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var last = Date.distantPast

    func allows(interval: TimeInterval) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        guard now.timeIntervalSince(last) >= interval else { return false }
        last = now
        return true
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        last = .distantPast
    }
}
