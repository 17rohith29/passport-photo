import CoreGraphics
import Foundation
import PhotoAnalysis
import PhotoPipeline
import Photos
import SpecKit
import SwiftUI
import UniformTypeIdentifiers

/// Saving is the only part of the flow that is app-specific. The processing state machine lives
/// in `PhotoPipeline.PhotoSession`, so the flow the app runs is the flow the tests drive.
@MainActor
@Observable
final class PhotoSaver {

    enum State: Equatable {
        case none
        case saving
        case savedToPhotos
        case permissionDenied
        case failed(String)
    }

    var state: State = .none

    func reset() { state = .none }

    /// Add-only Photos access: the app never reads the user's library.
    func saveToPhotos(_ data: Data) {
        state = .saving
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard let self else { return }
            guard status == .authorized || status == .limited else {
                Task { @MainActor in self.state = .permissionDenied }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            } completionHandler: { success, error in
                Task { @MainActor in
                    self.state = success
                        ? .savedToPhotos
                        : .failed(error?.localizedDescription ?? "Could not save.")
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
