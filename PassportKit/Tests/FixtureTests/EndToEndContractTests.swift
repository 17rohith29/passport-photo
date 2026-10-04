import CoreGraphics
import Foundation
import ImageIO
import SpecKit
import Testing
import TestSupport
@testable import PhotoAnalysis
@testable import PhotoPipeline

/// The whole contract, for every document, measured on the bytes that actually come out.
///
/// The other fixture suites check parts of this. This one runs a real photo end to end and then
/// opens the exported JPEG, because the thing a user submits is the file, not the CGImage.
@Suite("End to end contract", .serialized, .enabled(if: RepoPaths.hasFixturePhotos))
struct EndToEndContractTests {

    static func specs() throws -> [DocumentSpec] {
        let dir = try #require(RepoPaths.specs)
        return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.contains("schema") }
            .map { try SpecLoader.load(contentsOf: $0) }
            .filter { $0.status.isTestFixture != true }
            .sorted { $0.id < $1.id }
    }

    static func goldenPhoto() throws -> CGImage {
        let url = try #require(RepoPaths.fixtures).appendingPathComponent("photos/IMG_0012.HEIC")
        return try ImageLoader.load(data: try Data(contentsOf: url))
    }

    static func jpegProperties(_ data: Data) -> [CFString: Any]? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
    }

    @Test("every document: the exported file is what its spec promises")
    func exportedFileMatchesTheSpec() async throws {
        let image = try Self.goldenPhoto()
        let pipeline = PassportPipeline()
        var checked = 0

        for spec in try Self.specs() {
            let result = await pipeline.run(image, spec: spec)
            guard let output = result.output else {
                Issue.record("\(spec.id) produced no output: \(result.failures.map(\.id.rawValue))")
                continue
            }
            checked += 1
            let geometry = try #require(SpecGeometry(spec: spec), "\(spec.id)")
            let expected = try #require(spec.photo.digital.outputSizePx, "\(spec.id)")

            // 1. Pixel size is exactly what the spec asks for.
            #expect(output.digital.width == Int(expected.width), "\(spec.id) width")
            #expect(output.digital.height == Int(expected.height), "\(spec.id) height")

            // 2. The JPEG decodes, at that same size.
            let properties = try #require(Self.jpegProperties(output.digitalJPEG), "\(spec.id)")
            let pxWidth = properties[kCGImagePropertyPixelWidth] as? Int
            let pxHeight = properties[kCGImagePropertyPixelHeight] as? Int
            #expect(pxWidth == Int(expected.width), "\(spec.id) jpeg width \(pxWidth ?? -1)")
            #expect(pxHeight == Int(expected.height), "\(spec.id) jpeg height \(pxHeight ?? -1)")

            // 3. Its DPI prints at the physical size the spec states (LESSONS 31).
            let dpi = try #require(properties[kCGImagePropertyDPIHeight] as? Double, "\(spec.id)")
            let printedMM = expected.height / dpi * 25.4
            #expect(
                abs(printedMM - spec.photo.sizeMM.height) < 0.1,
                "\(spec.id) would print \(printedMM) mm tall, spec says \(spec.photo.sizeMM.height)"
            )

            // 4. The head sits inside the band the authority states.
            if let band = HeadHeightBand.inMM(spec: spec) {
                let headPx = Double(output.digital.height)
                    * (output.chinFraction - output.crownFraction)
                let headMM = geometry.pxToMM(headPx)
                #expect(
                    headMM >= band.min && headMM <= band.max,
                    "\(spec.id) head \(headMM) mm outside \(band.min)-\(band.max)"
                )
            }

            // 5. File size, where the authority states one.
            if let range = spec.photo.digital.fileSizeKB {
                #expect(
                    output.digitalSizeKB >= range.min && output.digitalSizeKB <= range.max,
                    "\(spec.id) file \(output.digitalSizeKB) KB outside \(range.min)-\(range.max)"
                )
            }

            // 6. The print sheet holds at least the copies the document demands.
            if output.printSheet != nil {
                let needed = spec.photo.print.copiesRequired ?? 1
                #expect(
                    PrintGuidance.photosPerSheet(spec: spec) >= needed,
                    "\(spec.id) needs \(needed) copies, sheet holds \(PrintGuidance.photosPerSheet(spec: spec))"
                )
            }

            // 7. The verdict and the checks agree.
            if result.verdict == .meetsRequirements {
                #expect(result.failures.isEmpty, "\(spec.id) passed with failures")
            }
        }
        #expect(checked >= 8, "only \(checked) documents produced output")
    }

    /// A square photo is the case most likely to be got wrong, and there are now two.
    @Test("square documents are not stretched")
    func squareDocumentsKeepTheirShape() async throws {
        let image = try Self.goldenPhoto()
        for spec in try Self.specs() where spec.photo.sizeMM.width == spec.photo.sizeMM.height {
            let expected = try #require(spec.photo.digital.outputSizePx, "\(spec.id)")
            #expect(expected.width == expected.height, "\(spec.id) square mm but non-square px")

            let result = await PassportPipeline().run(image, spec: spec)
            guard let out = result.output?.digital else { continue }
            #expect(out.width == out.height, "\(spec.id) output \(out.width)x\(out.height)")
        }
    }

    /// Every document's pixel shape must match its physical shape, or faces stretch (LESSONS 26).
    @Test("pixel aspect matches physical aspect for every document")
    func aspectRatiosAgree() throws {
        for spec in try Self.specs() {
            let px = try #require(spec.photo.digital.outputSizePx, "\(spec.id)")
            let pixelAspect = px.width / px.height
            let physicalAspect = spec.photo.sizeMM.width / spec.photo.sizeMM.height
            let stretch = abs(pixelAspect - physicalAspect) / physicalAspect
            #expect(stretch < 0.002, "\(spec.id) stretches faces by \(stretch * 100)%")
        }
    }
}
