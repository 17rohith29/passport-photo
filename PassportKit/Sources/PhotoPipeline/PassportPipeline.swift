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
}

public struct PipelineResult: Sendable {
    public var verdict: Verdict
    public var inputChecks: [CheckResult]
    public var outputChecks: [CheckResult]
    public var output: RenderedOutput?
    public var failureReason: String?

    public var allChecks: [CheckResult] { inputChecks + outputChecks }

    public var failures: [CheckResult] { allChecks.filter { $0.status == .fail } }
    public var warnings: [CheckResult] { allChecks.filter { $0.status == .warn } }
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

    public func run(_ image: CGImage, spec: DocumentSpec) async -> PipelineResult {
        do {
            return try await execute(image, spec: spec)
        } catch {
            return PipelineResult(
                verdict: .cannotUse, inputChecks: [], outputChecks: [], output: nil,
                failureReason: "\(error)"
            )
        }
    }

    private func execute(_ image: CGImage, spec: DocumentSpec) async throws -> PipelineResult {
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

        // 3. Segment and refine.
        let rawMatte = try await segmenter.matte(for: levelled)
        let matte = MatteRefiner.refine(
            matte: rawMatte, image: levelledPixels, face: levelledFace, tuning: tuning
        )

        // 4. Crown and chin, then the crop.
        guard let crown = CrownFinder.find(matte: matte, face: levelledFace, tuning: tuning) else {
            throw PipelineError.crownNotFound
        }
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
            source: levelledPixels, matte: matte, plan: plan,
            background: background, sharpen: tuning.sharpenDigital, tuning: tuning
        ), let digitalImage = ImageConversion.cgImage(from: digital) else {
            throw PipelineError.renderFailed
        }

        let dpi = spec.photo.print.dpi
        guard let jpeg = JPEGExporter.encode(
            digitalImage, dpi: dpi, fileSizeKB: spec.photo.digital.fileSizeKB, tuning: tuning
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
            source: levelledPixels, matte: matte, plan: tilePlan,
            background: background, sharpen: tuning.sharpenPrint, tuning: tuning
        ), let sheet = PrintSheetComposer.compose(tile: tile, spec: spec),
           let sheetImage = ImageConversion.cgImage(from: sheet.image) {
            printSheetImage = sheetImage
            printSheetData = JPEGExporter.encode(sheetImage, dpi: dpi, fileSizeKB: nil, tuning: tuning)?.data
        }

        // 6. Re-measure the finished file (LESSONS 13).
        let checker = ComplianceChecker(analyzer: analyzer, segmenter: segmenter, tuning: tuning)
        let outputChecks = await checker.check(
            output: digitalImage, jpegSizeKB: jpeg.sizeKB, spec: spec
        )

        let output = RenderedOutput(
            digital: digitalImage, digitalJPEG: jpeg.data, digitalSizeKB: jpeg.sizeKB,
            printSheet: printSheetImage, printSheetJPEG: printSheetData,
            crownY: crown, chinY: chin, headHeightPx: chin - crown
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
