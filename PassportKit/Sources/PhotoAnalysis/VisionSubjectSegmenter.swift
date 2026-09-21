import CoreGraphics
import CoreImage
import Foundation
import Vision

public protocol SubjectSegmenting: Sendable {
    func matte(for image: CGImage) async throws -> AlphaMatte
}

/// Subject cut-out from Vision. Replaces rembg/isnet from the reference pipeline.
///
/// Two sources are available and they fail differently: person segmentation is trained on people
/// and holds up around hair, while the foreground instance mask is sharper but sometimes takes
/// the whole upper body plus nearby clutter. `.preferred` runs person segmentation and falls
/// back to the instance mask only if it comes back empty.
public struct VisionSubjectSegmenter: SubjectSegmenting {

    public enum Source: Sendable {
        case personSegmentation
        case foregroundInstanceMask
        case preferred
    }

    public var source: Source

    public init(source: Source = .preferred) {
        self.source = source
    }

    public func matte(for image: CGImage) async throws -> AlphaMatte {
        switch source {
        case .personSegmentation:
            return try await personMatte(for: image)
        case .foregroundInstanceMask:
            return try await instanceMatte(for: image)
        case .preferred:
            // Person segmentation can fail outright, not just come back empty: in the iOS
            // Simulator it throws "Could not create inference context" (Vision code 9), which
            // rejected every photo with a raw Vision dump. Treat a throw and an empty mask the
            // same way and fall through to the instance mask.
            var personFailure: Error?
            do {
                let person = try await personMatte(for: image)
                if coverage(person) > 0.01 { return person }
            } catch {
                personFailure = error
            }
            do {
                return try await instanceMatte(for: image)
            } catch {
                throw SegmentationError.bothSourcesFailed(
                    person: personFailure.map { "\($0)" }, instance: "\(error)"
                )
            }
        }
    }

    func personMatte(for image: CGImage) async throws -> AlphaMatte {
        let request = GeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        let observation = try await request.perform(on: image, orientation: .up)
        guard let matte = ImageConversion.matte(from: try observation.cgImage) else {
            throw SegmentationError.maskUnavailable
        }
        return matte.resized(width: image.width, height: image.height)
    }

    func instanceMatte(for image: CGImage) async throws -> AlphaMatte {
        let request = GenerateForegroundInstanceMaskRequest()
        guard let observation = try await request.perform(on: image, orientation: .up) else {
            throw SegmentationError.maskUnavailable
        }
        let handler = ImageRequestHandler(image, orientation: .up)
        let buffer = try observation.generateScaledMask(
            for: observation.allInstances, scaledToImageFrom: handler
        )
        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard let cgImage = CIContext().createCGImage(ciImage, from: ciImage.extent),
              let matte = ImageConversion.matte(from: cgImage) else {
            throw SegmentationError.maskUnavailable
        }
        return matte.resized(width: image.width, height: image.height)
    }

    private func coverage(_ matte: AlphaMatte) -> Double {
        guard !matte.values.isEmpty else { return 0 }
        let inside = matte.values.reduce(0.0) { $0 + ($1 > 0.5 ? 1 : 0) }
        return inside / Double(matte.values.count)
    }
}

public enum SegmentationError: Error, CustomStringConvertible {
    case maskUnavailable
    case bothSourcesFailed(person: String?, instance: String)

    public var description: String {
        switch self {
        case .maskUnavailable:
            return "Could not separate you from the background."
        case let .bothSourcesFailed(person, instance):
            var text = "Could not separate you from the background. Instance mask: \(instance)."
            if let person { text += " Person segmentation: \(person)." }
            return text
        }
    }
}
