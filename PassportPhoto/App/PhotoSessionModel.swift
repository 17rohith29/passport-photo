import CoreGraphics
import Foundation
import PhotoAnalysis
import PhotoPipeline
import Photos
import SpecKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class PhotoSessionModel {

    enum Stage: Equatable {
        case idle
        case working(step: String)
        case rejected
        case finished
    }

    enum SaveState: Equatable {
        case none
        case saving
        case savedToPhotos
        case permissionDenied
        case failed(String)
    }

    var stage: Stage = .idle
    var sourceImage: CGImage?
    var result: PipelineResult?
    var saveState: SaveState = .none
    var loadError: String?

    private let pipeline = PassportPipeline()
    private var task: Task<Void, Never>?

    var checks: [CheckResult] { result?.allChecks ?? [] }
    var failures: [CheckResult] { result?.failures ?? [] }
    var warnings: [CheckResult] { result?.warnings ?? [] }
    var output: RenderedOutput? { result?.output }

    var isWorking: Bool {
        if case .working = stage { return true }
        return false
    }

    func process(data: Data, spec: DocumentSpec) {
        cancel()
        reset()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                self.stage = .working(step: "Reading your photo")
                let image = try ImageLoader.load(data: data)
                guard !Task.isCancelled else { return }
                self.sourceImage = image

                self.stage = .working(step: "Checking quality and finding your face")
                let outcome = await self.pipeline.run(image, spec: spec)
                guard !Task.isCancelled else { return }

                self.result = outcome
                self.stage = outcome.output == nil ? .rejected : .finished
            } catch {
                self.loadError = "\(error)"
                self.stage = .rejected
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    func reset() {
        result = nil
        sourceImage = nil
        saveState = .none
        loadError = nil
        stage = .idle
    }

    /// Add-only Photos access: the app never reads the user's library.
    func saveToPhotos(_ data: Data) {
        saveState = .saving
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard let self else { return }
            guard status == .authorized || status == .limited else {
                Task { @MainActor in self.saveState = .permissionDenied }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            } completionHandler: { success, error in
                Task { @MainActor in
                    self.saveState = success ? .savedToPhotos : .failed(error?.localizedDescription ?? "Could not save.")
                }
            }
        }
    }
}

/// Wraps JPEG data so `fileExporter` can write it out.
struct JPEGDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.jpeg] }

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
