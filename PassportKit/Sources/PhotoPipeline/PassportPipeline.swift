import CoreGraphics
import Foundation
import PhotoAnalysis
import SpecKit

public struct RenderedOutput: Sendable {
    public var digital: CGImage
    public var digitalJPEG: Data
    public var digitalSizeKB: Double
    public var printSheet: CGImage?
    public var printSheetJPEG: Data?
    public var crownY: CGFloat
    public var chinY: CGFloat
    public var headHeightPx: CGFloat
    /// Where the crown and chin actually landed in the finished photo, as fractions of its
    /// height from the top. The measurements overlay draws these, so it shows what was measured
    /// rather than what the spec asked for.
    public var crownFraction: Double
    public var chinFraction: Double
}

public struct PipelineResult: Sendable {
    public var verdict: Verdict
    public var inputChecks: [CheckResult]
    public var outputChecks: [CheckResult]
    public var output: RenderedOutput?
    /// Plain language, for the user.
    public var failureReason: String?
    /// The underlying error, for a bug report. Never the headline.
    public var technicalDetail: String?
    /// True when the run failed because of what this device can do, not the photo. The UI must
    /// not tell someone to pick a different photo when no photo would work.
    public var isDeviceLimitation: Bool = false

    public var allChecks: [CheckResult] { inputChecks + outputChecks }

    public var failures: [CheckResult] { allChecks.filter { $0.status == .fail } }
    public var warnings: [CheckResult] { allChecks.filter { $0.status == .warn } }
}

/// The stages the pipeline reports as it works, so the UI can show real progress rather than a
/// spinner that never moves.
public enum PipelineStage: String, Sendable, CaseIterable {
    case reading = "Reading your photo"
    case checking = "Checking quality and finding your face"
    case separating = "Separating you from the background"
    case cropping = "Cropping to size"
    case verifying = "Verifying the result"
}

/// Orchestrates the whole run. Every stage behind it is a protocol or a pure function, so tests
/// can drive any part in isolation.
public actor PassportPipeline {

    private let analyzer: any FaceAnalyzing
    private let segmenter: any SubjectSegmenting
    private let tuning: Tuning
    private let calibration: GateCalibration

    public init(
        analyzer: any FaceAnalyzing = VisionFaceAnalyzer(),
        segmenter: any SubjectSegmenting = VisionSubjectSegmenter(),
        tuning: Tuning = .default,
        calibration: GateCalibration = .default
    ) {
        self.analyzer = analyzer
        self.segmenter = segmenter
        self.tuning = tuning
        self.calibration = calibration
    }

    public func run(
        _ image: CGImage, spec: DocumentSpec,
        onStage: (@Sendable (PipelineStage) -> Void)? = nil
    ) async -> PipelineResult {
        do {
            return try await execute(image, spec: spec, onStage: onStage)
        } catch {
            return PipelineResult(
                verdict: .cannotUse, inputChecks: [], outputChecks: [], output: nil,
                failureReason: Self.plainMessage(for: error),
                technicalDetail: "\(error)",
                isDeviceLimitation: Self.isDeviceLimitation(error)
            )
        }
    }

    /// A Vision or rendering failure is not the user's fault and is not something they can fix by
    /// choosing a different photo, so it must not be dressed up as a photo problem — nor dumped
    /// on them as a raw error string.
    static func plainMessage(for error: Error) -> String {
        // Vision's ML models cannot create an inference context in the iOS Simulator, so every
        // request fails there before any photo problem is even measured. It is not the user's
        // photo that is wrong, and no other photo will work either.
        if isDeviceLimitation(error) {
            // Vision can also fail to build an inference context on a real device - memory
            // pressure, thermal throttling, an OS fault. Telling someone holding an iPhone that
            // they need a real iPhone, and naming the Simulator, is the worst string we could
            // ship, and it gives them nothing to do.
            #if targetEnvironment(simulator)
            return """
            Photo processing needs a real iPhone. Vision's models are unavailable in the iOS \
            Simulator: on iOS 26 they fail outright, and on iOS 18 they quietly find no face. \
            Nothing can be measured here, and no other photo will work either.
            """
            #else
            return """
            This iPhone couldn't start the photo analysis. Close a few apps or restart the \
            phone, then try again. Nothing about the photo itself is the problem.
            """
            #endif
        }
        switch error {
        case is SegmentationError:
            return "This device couldn't separate you from the background."
        case FaceAnalysisError.noFaceFound:
            return "We couldn't find a face in this photo."
        case let FaceAnalysisError.multipleFaces(count):
            return "We found \(count) faces. The photo must have only you in it."
        case PipelineError.crownNotFound:
            return "We couldn't find the top of your head. Make sure your whole head is in the photo."
        case PipelineError.undecodable:
            return "That file couldn't be read as a photo."
        default:
            return "Something went wrong while processing this photo on this device."
        }
    }

    /// Failures that are the device's rather than the photo's.
    ///
    /// Vision code 9, "Could not create inference context", means the ML models are unavailable
    /// (matched on the message because the case carries no structured code). In the Simulator the
    /// same unavailability also shows up as an empty result, which is indistinguishable from a
    /// genuine "no face" — so there, treat that as a device limitation too rather than telling
    /// someone their photo has no face in it.
    static func isDeviceLimitation(_ error: Error) -> Bool {
        let text = "\(error)"
        if text.contains("Could not create inference context") || text.contains("Vision Code=9") {
            return true
        }
        #if targetEnvironment(simulator)
        if case FaceAnalysisError.noFaceFound = error { return true }
        if error is SegmentationError { return true }
        #endif
        return false
    }

    private func execute(
        _ image: CGImage, spec: DocumentSpec,
        onStage: (@Sendable (PipelineStage) -> Void)?
    ) async throws -> PipelineResult {
        // Cancellation is checked at every stage boundary. Without these, `cancel()` only
        // discarded the answer while the work ran on - and because the pipeline is an actor
        // held for the whole session, the next photo queued behind the abandoned run.
        try Task.checkCancellation()
        onStage?(.checking)
        // 1. Analyse the photo as imported.
        let face = try await analyzer.analyze(image)
        guard let pixels = ImageConversion.pixelImage(from: image) else {
            throw PipelineError.undecodable
        }
        let luminance = ImageConversion.luminance(of: pixels)

        let sharpness = ImageMetrics.sharpness(luminance: luminance, faceBox: face.boundingBox)
        let cheek = ImageMetrics.cheekImbalance(luminance: luminance, face: face, tuning: tuning)

        // Head height before segmentation, so a photo that is far too small is rejected without
        // paying for a matte. Uses the refined chin and a brow-based crown estimate.
        let refinedChin = ChinRefiner.refine(luminance: luminance, face: face, tuning: tuning)
        let estimatedHead = Double(refinedChin - face.browY) * 1.64

        var inputChecks = InputGate.evaluate(
            face: face, sharpness: sharpness, cheekImbalance: cheek,
            headHeightPx: estimatedHead, imageSize: pixels.size,
            spec: spec, calibration: calibration
        )

        if inputChecks.contains(where: { $0.status == .fail }) {
            return PipelineResult(
                verdict: .cannotUse, inputChecks: inputChecks, outputChecks: [], output: nil
            )
        }

        // 2. Level, then re-analyse: every later measurement is on the levelled image.
        let levelled = Leveler.level(
            image, byDegrees: face.eyeLineAngleDeg, about: face.eyeMidpoint
        ) ?? image
        let levelledFace = try await analyzer.analyze(levelled)
        guard let levelledPixels = ImageConversion.pixelImage(from: levelled) else {
            throw PipelineError.undecodable
        }
        let levelledLuminance = ImageConversion.luminance(of: levelledPixels)

        // 3. Segment and refine at a reduced working resolution.
        //
        // MatteRefiner allocates several buffers the size of the image: connected components,
        // a signed distance field and a blur. At 24 MP that is hundreds of megabytes, which a
        // Mac absorbs and a phone does not. The reference pipeline downsamples for the same
        // reason (`matte(..., work=2600)`). The matte then stays at this size and the renderer
        // samples it, rather than being upscaled into another full-size buffer.
        try Task.checkCancellation()
        onStage?(.separating)
        let workScale = ImageLoader.workingScale(for: levelled, longestEdge: tuning.matteWorkingSize)
        let workImage = ImageLoader.resized(levelled, scale: workScale) ?? levelled
        guard let workPixels = ImageConversion.pixelImage(from: workImage) else {
            throw PipelineError.undecodable
        }
        let workFace = levelledFace.scaled(by: workScale)

        let rawMatte = try await segmenter.matte(for: workImage)
        let matte = MatteRefiner.refine(
            matte: rawMatte, image: workPixels, face: workFace, tuning: tuning
        )

        // 4. Crown and chin, then the crop. The crown is found in working pixels and scaled back.
        try Task.checkCancellation()
        onStage?(.cropping)

        // A photo cropped above the hairline still yields a crown - the clipped edge - and then
        // passes headHeight and topMargin while the top of the head is simply missing.
        if CrownFinder.touchesTopEdge(matte: matte, face: workFace, tuning: tuning) {
            inputChecks.append(CheckResult(
                id: .headroom, status: .fail,
                measured: "the top of your head is outside the photo",
                requirement: "the whole head, with space above it",
                userMessage: "The top of your head is cut off. Use a photo with space above your hair.",
                fixability: .retakeRequired
            ))
            return PipelineResult(
                verdict: .cannotUse, inputChecks: inputChecks, outputChecks: [], output: nil
            )
        }

        guard let workCrown = CrownFinder.find(matte: matte, face: workFace, tuning: tuning) else {
            throw PipelineError.crownNotFound
        }
        let crown = workCrown / CGFloat(workScale)
        let chin = ChinRefiner.refine(luminance: levelledLuminance, face: levelledFace, tuning: tuning)

        let planResult = CropPlanner.plan(
            crown: crown, chin: chin,
            eyes: (levelledFace.leftEye, levelledFace.rightEye),
            imageSize: levelledPixels.size, spec: spec
        )
        let plan: CropPlan
        switch planResult {
        case let .success(value):
            plan = value
        case let .failure(error):
            // A planner refusal is a real rejection, reported like any other check.
            inputChecks.append(CheckResult(
                id: .resolution, status: .fail,
                measured: "\(error)", requirement: "no upscaling",
                userMessage: "Take the photo from closer, about 1.5 m, using the 2x lens.",
                fixability: .retakeRequired
            ))
            return PipelineResult(
                verdict: .cannotUse, inputChecks: inputChecks, outputChecks: [], output: nil
            )
        }

        // 5. Render both outputs from the source, never from each other (LESSONS 4).
        let background = RGB(hex: spec.background?.colorHex ?? "#FFFFFF") ?? .white
        guard let digital = Renderer.render(
            source: levelledPixels, matte: matte, matteScale: workScale, plan: plan,
            background: background, sharpen: tuning.sharpenDigital, tuning: tuning
        ), let digitalImage = ImageConversion.cgImage(from: digital) else {
            throw PipelineError.renderFailed
        }

        let dpi = spec.photo.print.dpi
        guard let jpeg = JPEGExporter.encode(
            digitalImage, dpi: SpecGeometry(spec: spec)?.digitalDPI ?? dpi,
            fileSizeKB: spec.photo.digital.fileSizeKB, tuning: tuning
        ) else {
            throw PipelineError.renderFailed
        }

        let tileSize = SpecGeometry.printTilePx(spec: spec)
        var printSheetImage: CGImage?
        var printSheetData: Data?
        let tilePlan = CropPlan(
            rect: plan.rect,
            outputSize: CGSize(width: tileSize.width, height: tileSize.height),
            scale: plan.rect.height / tileSize.height
        )
        if let tile = Renderer.render(
            source: levelledPixels, matte: matte, matteScale: workScale, plan: tilePlan,
            background: background, sharpen: tuning.sharpenPrint, tuning: tuning
        ), let sheet = PrintSheetComposer.compose(tile: tile, spec: spec),
           let sheetImage = ImageConversion.cgImage(from: sheet.image) {
            printSheetImage = sheetImage
            printSheetData = JPEGExporter.encode(sheetImage, dpi: dpi, fileSizeKB: nil, tuning: tuning)?.data
        }

        // 6. Re-measure the finished file (LESSONS 13).
        try Task.checkCancellation()
        onStage?(.verifying)
        let checker = ComplianceChecker(analyzer: analyzer, segmenter: segmenter, tuning: tuning)
        let outputChecks = await checker.check(
            output: digitalImage, jpegSizeKB: jpeg.sizeKB, spec: spec
        )

        let output = RenderedOutput(
            digital: digitalImage, digitalJPEG: jpeg.data, digitalSizeKB: jpeg.sizeKB,
            printSheet: printSheetImage, printSheetJPEG: printSheetData,
            crownY: crown, chinY: chin, headHeightPx: chin - crown,
            crownFraction: Double((crown - plan.rect.minY) / plan.rect.height),
            chinFraction: Double((chin - plan.rect.minY) / plan.rect.height)
        )

        return PipelineResult(
            verdict: Verdict.from(inputChecks + outputChecks),
            inputChecks: inputChecks, outputChecks: outputChecks, output: output
        )
    }
}

public enum PipelineError: Error, CustomStringConvertible {
    case undecodable
    case crownNotFound
    case renderFailed

    public var description: String {
        switch self {
        case .undecodable: return "The photo could not be decoded."
        case .crownNotFound: return "Could not find the top of your head."
        case .renderFailed: return "Could not produce the finished photo."
        }
    }
}
