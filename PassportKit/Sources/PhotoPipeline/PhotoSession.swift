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
    private let maxPixelSize: Int
    private var task: Task<Void, Never>?

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

    public func process(data: Data, spec: DocumentSpec) {
        cancel()
        reset()
        task = Task { await self.run(data: data, spec: spec) }
    }

    /// Same work, awaitable. Tests use this; the app uses `process`.
    public func processAndWait(data: Data, spec: DocumentSpec) async {
        cancel()
        reset()
        await run(data: data, spec: spec)
    }

    private func run(data: Data, spec: DocumentSpec) async {
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

            let outcome = await pipeline.run(image, spec: spec) { [weak self] stage in
                Task { @MainActor [weak self] in
                    guard let self, self.isWorking else { return }
                    if let current = self.currentStage { self.completed.insert(current) }
                    self.phase = .working(stage)
                }
            }
            guard !Task.isCancelled else { return }

            completed.formUnion(PipelineStage.allCases)
            result = outcome
            phase = outcome.output == nil ? .rejected : .finished
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
    }
}
