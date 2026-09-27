import CoreGraphics
import Foundation
import ImageIO
import SpecKit
import Testing
@testable import PhotoAnalysis
@testable import PhotoPipeline

/// The DPI stamped into a JPEG is not cosmetic: a print shop that honours it decides the
/// physical size from it. These read the metadata back out of the encoded bytes.
@Suite("Export metadata")
struct ExportMetadataTests {

    static func image(width: Int, height: Int) -> CGImage? {
        var pixels = PixelImage(width: width, height: height, fill: (255, 255, 255))
        // Some content, so the encoder cannot collapse it to something degenerate.
        for y in 0..<height where y % 3 == 0 {
            for x in 0..<width where x % 3 == 0 {
                let offset = pixels.offset(x: x, y: y)
                pixels.pixels[offset] = 40
                pixels.pixels[offset + 1] = 60
                pixels.pixels[offset + 2] = 90
            }
        }
        return ImageConversion.cgImage(from: pixels)
    }

    static func readDPI(_ data: Data) -> (width: Double, height: Double)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let w = properties[kCGImagePropertyDPIWidth] as? Double,
              let h = properties[kCGImagePropertyDPIHeight] as? Double else { return nil }
        return (w, h)
    }

    @Test("the encoder writes the DPI it was given")
    func dpiRoundTrips() throws {
        let image = try #require(Self.image(width: 63, height: 81))
        for dpi in [300.0, 457.2, 600.0] {
            let output = try #require(JPEGExporter.encode(image, dpi: dpi, fileSizeKB: nil))
            let read = try #require(Self.readDPI(output.data))
            #expect(abs(read.width - dpi) < 1.0, "wrote \(dpi), read \(read.width)")
            #expect(abs(read.height - dpi) < 1.0)
        }
    }

    /// The bug this guards: stamping print.dpi into the digital file made a 630x810 photo
    /// print at 53x69 mm instead of 35x45 mm, 52% too large.
    @Test("each document's digital DPI would print the file at its real physical size")
    func everyDocumentPrintsAtItsStatedSize() throws {
        for spec in try PrintGuidanceTests.specs() {
            let geometry = try #require(SpecGeometry(spec: spec), "\(spec.id)")
            let px = try #require(spec.photo.digital.outputSizePx)
            // A small stand-in: only the metadata is under test, not the pixels.
            let image = try #require(Self.image(width: 63, height: 81))
            let output = try #require(
                JPEGExporter.encode(image, dpi: geometry.digitalDPI, fileSizeKB: nil), "\(spec.id)"
            )
            let read = try #require(Self.readDPI(output.data), "\(spec.id)")

            let printedHeightMM = px.height / read.height * 25.4
            #expect(
                abs(printedHeightMM - spec.photo.sizeMM.height) < 0.1,
                "\(spec.id) would print \(printedHeightMM) mm tall, spec says \(spec.photo.sizeMM.height)"
            )
            // And it must NOT be the print-tile density, which is what the bug used.
            if abs(geometry.digitalDPI - spec.photo.print.dpi) > 1 {
                #expect(abs(read.height - spec.photo.print.dpi) > 1, "\(spec.id) still stamps print.dpi")
            }
        }
    }

    @Test("a print tile at print.dpi is the physical size too")
    func printTileIsPhysicallyCorrect() throws {
        for spec in try PrintGuidanceTests.specs() {
            let tile = SpecGeometry.printTilePx(spec: spec)
            let heightMM = tile.height / spec.photo.print.dpi * 25.4
            let widthMM = tile.width / spec.photo.print.dpi * 25.4
            #expect(abs(heightMM - spec.photo.sizeMM.height) < 0.1, "\(spec.id) tile height")
            #expect(abs(widthMM - spec.photo.sizeMM.width) < 0.1, "\(spec.id) tile width")
        }
    }
}
