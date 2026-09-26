import CoreGraphics
import Foundation
import Observation
import PhotoAnalysis
import SpecKit

/// Drives one photo through the pipeline and publishes what stage it is at.
///
/// Lives here rather than in the app so the flow the app actually runs can be tested end to end.
/// It imports Observation, never SwiftUI or UIKit.
@MainActor
@Observable
public final class PhotoSession {

    public enum Phase: Equatable, Sendable {
        case idle
        case working(PipelineStage)
        case rejected
        case finished
    }

    public private(set) var phase: Phase = .idle
    /// Stages finished so far, so the UI can tick them off instead of showing a stuck spinner.
    public private(set) var completed: Set<PipelineStage> = []
    public private(set) var sourceImage: CGImage?
    public private(set) var result: PipelineResult?
    public private(set) var loadError: String?

    private let pipeline: PassportPipeline
    /// The cap used when a resolution rejection is retried. Higher than the normal decode cap,
    /// but still a cap: a 48 MP decode holds roughly a gigabyte of intermediate planes.
    nonisolated static let retryMaxPixelSize = 7000

    private let maxPixelSize: Int
    private var task: Task<Void, Never>?
    /// Identifies the run a stage report belongs to. Cancelling a run does not stop the work
    /// inside the pipeline, so a cancelled run's reports would otherwise keep arriving and
    /// drive the NEXT photo's progress screen.
    private var runToken = 0

    public init(
        pipeline: PassportPipeline = PassportPipeline(),
        maxPixelSize: Int = ImageLoader.defaultMaxPixelSize
    ) {
        self.pipeline = pipeline
        self.maxPixelSize = maxPixelSize
    }

    public var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }

    public var currentStage: PipelineStage? {
        if case let .working(stage) = phase { return stage }
        return nil
    }

    /// Why the run stopped, when no individual check failed — a stage threw. Without surfacing
    /// this the rejection screen is a dead end saying only "this photo can't be used".
    public var failureReason: String? { loadError ?? result?.failureReason }

    /// The underlying error, for a bug report. Shown small, never as the headline.
    public var technicalDetail: String? { result?.technicalDetail }

    /// The failure is this device's, not the photo's.
    public var isDeviceLimitation: Bool { result?.isDeviceLimitation ?? false }

    public var checks: [CheckResult] { result?.allChecks ?? [] }
    public var failures: [CheckResult] { result?.failures ?? [] }
    public var warnings: [CheckResult] { result?.warnings ?? [] }
    public var output: RenderedOutput? { result?.output }

    /// Kept so the run can be repeated in the other background mode without re-importing.
    private var lastData: Data?
    private var lastSpec: DocumentSpec?

    public func process(data: Data, spec: DocumentSpec, mode: BackgroundMode? = nil) {
        cancel()
        reset()
        lastData = data
        lastSpec = spec
        let resolved = mode ?? BackgroundMode.default(for: spec)
        task = Task { await self.run(data: data, spec: spec, mode: resolved) }
    }

    /// Same work, awaitable. Tests use this; the app uses `process`.
    public func processAndWait(
        data: Data, spec: DocumentSpec, mode: BackgroundMode? = nil
    ) async {
        cancel()
        reset()
        lastData = data
        lastSpec = spec
        await run(data: data, spec: spec, mode: mode ?? BackgroundMode.default(for: spec))
    }

    /// Re-runs the photo already imported, in the other background mode. Used when keeping the
    /// user's own wall did not pass and they choose to replace it anyway.
    public func reprocess(mode: BackgroundMode) {
        guard let data = lastData, let spec = lastSpec else { return }
        let keptData = data
        let keptSpec = spec
        cancel()
        reset()
        lastData = keptData
        lastSpec = keptSpec
        task = Task { await self.run(data: keptData, spec: keptSpec, mode: mode) }
    }

    /// The mode the current result was produced in.
    public var backgroundMode: BackgroundMode { result?.backgroundMode ?? .replace }
    public var isUnedited: Bool { result?.isUnedited ?? false }

    private func run(data: Data, spec: DocumentSpec, mode: BackgroundMode) async {
        runToken &+= 1
        let token = runToken
        let report: @Sendable (PipelineStage) -> Void = { [weak self] stage in
            Task { @MainActor [weak self] in
                guard let self, self.runToken == token, self.isWorking else { return }
                if let current = self.currentStage { self.completed.insert(current) }
                self.phase = .working(stage)
            }
        }
        phase = .working(.reading)
        do {
            // Decoding a 24 MP HEIC would stutter the UI on the main actor.
            let size = maxPixelSize
            let image = try await Task.detached(priority: .userInitiated) {
                try ImageLoader.load(data: data, maxPixelSize: size)
            }.value
            guard !Task.isCancelled else { return }
            sourceImage = image
            completed.insert(.reading)

            var outcome = await pipeline.run(image, spec: spec, mode: mode, onStage: report)
            guard !Task.isCancelled else { return }

            // The decode cap shrinks the frame, which shrinks the head with it. A photo whose
            // head clears the requirement at full resolution can fall under it once capped, so a
            // resolution rejection is retried at full size before it is believed. Nothing else
            // is retried: every other rejection is about the photo, not the decode.
            if outcome.output == nil,
               outcome.failures.contains(where: { $0.id == .resolution }),
               let full = ImageLoader.pixelSize(data: data),
               Int(max(full.width, full.height)) > maxPixelSize {
                // Still capped, just higher: an uncapped 48 MP decode holds several hundred MB
                // of intermediate planes at once, and the retry exists for head pixels, not for
                // every pixel.
                if let fullImage = try? await Task.detached(priority: .userInitiated, operation: {
                    try ImageLoader.load(data: data, maxPixelSize: Self.retryMaxPixelSize)
                }).value {
                    guard !Task.isCancelled else { return }
                    // The retry re-runs every stage, so the ticks have to go back to the start.
                    // Leaving them all green showed five checkmarks and no spinner through the
                    // slowest pass the app ever does - indistinguishable from a hang.
                    completed = [.reading]
                    phase = .working(.checking)
                    let retry = await pipeline.run(
                        fullImage, spec: spec, mode: mode, onStage: report
                    )
                    if retry.output != nil {
                        sourceImage = fullImage
                        outcome = retry
                    }
                }
            }
            guard !Task.isCancelled else { return }

            completed.formUnion(PipelineStage.allCases)
            result = outcome
            // Branching on "did we produce pixels" let a photo the app had already judged
            // unusable reach the result screen, under a prominent Save button. The verdict is
            // what decides, not whether a render happened.
            phase = (outcome.output == nil || outcome.verdict == .cannotUse) ? .rejected : .finished
            // The result screen never reads the source, and at the retry cap it is ~147 MB.
            if phase == .finished { sourceImage = nil }
        } catch {
            loadError = "\(error)"
            phase = .rejected
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }

    public func reset() {
        task?.cancel()
        task = nil
        result = nil
        completed = []
        sourceImage = nil
        loadError = nil
        phase = .idle
        // A 24 MP import is tens of megabytes; it is kept only so the run can be repeated in
        // the other background mode, and `reprocess` restores it around its own reset.
        lastData = nil
        lastSpec = nil
    }
}
