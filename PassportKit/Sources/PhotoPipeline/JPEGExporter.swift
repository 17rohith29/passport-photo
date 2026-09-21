import CoreGraphics
import Foundation
import ImageIO
import PhotoAnalysis
import SpecKit
import UniformTypeIdentifiers

/// Writes JPEG data that lands inside the spec's KB range.
///
/// Quality steps down; the image is never resized to hit a file size (LESSONS 4).
public enum JPEGExporter {

    public struct Output: Sendable {
        public var data: Data
        public var quality: Double
        public var sizeKB: Double
    }

    public static func encode(
        _ image: CGImage, dpi: Double, fileSizeKB: SpecKit.Range?, tuning: Tuning = .default
    ) -> Output? {
        var quality = tuning.jpegStartQuality
        var best: Output?

        while quality >= tuning.jpegMinQuality {
            guard let data = jpegData(image, quality: quality, dpi: dpi) else { return best }
            let sizeKB = Double(data.count) / 1024
            let output = Output(data: data, quality: quality, sizeKB: sizeKB)
            best = output

            guard let range = fileSizeKB else { return output }
            if sizeKB <= range.max { return output }
            quality -= tuning.jpegQualityStep
        }
        return best
    }

    static func jpegData(_ image: CGImage, quality: Double, dpi: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }

        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

/// Lays finished photos out on a sheet of paper at exactly 100% scale.
///
/// LESSONS 4: tiles are rendered from the source, never by shrinking the digital file.
/// The grid is computed from the spec, never hard-coded to 2x3 (ARCHITECTURE).
public enum PrintSheetComposer {

    public struct Sheet: Sendable {
        public var image: PixelImage
        public var columns: Int
        public var rows: Int
        public var paperSizeInches: CGSize
    }

    public static func compose(
        tile: PixelImage, spec: DocumentSpec,
        paperSizeInches: CGSize = CGSize(width: 4, height: 6),
        gutterPx: Int = 40
    ) -> Sheet? {
        let dpi = spec.photo.print.dpi
        let sheetWidth = Int((paperSizeInches.width * dpi).rounded())
        let sheetHeight = Int((paperSizeInches.height * dpi).rounded())
        guard sheetWidth > 0, sheetHeight > 0, tile.width > 0, tile.height > 0 else { return nil }

        let columns = max(1, (sheetWidth + gutterPx) / (tile.width + gutterPx))
        let rows = max(1, (sheetHeight + gutterPx) / (tile.height + gutterPx))

        var sheet = PixelImage(width: sheetWidth, height: sheetHeight, fill: (255, 255, 255))
        let gridWidth = columns * tile.width + (columns - 1) * gutterPx
        let gridHeight = rows * tile.height + (rows - 1) * gutterPx
        let originX = max(0, (sheetWidth - gridWidth) / 2)
        let originY = max(0, (sheetHeight - gridHeight) / 2)

        for row in 0..<rows {
            for column in 0..<columns {
                let x = originX + column * (tile.width + gutterPx)
                let y = originY + row * (tile.height + gutterPx)
                blit(tile, into: &sheet, atX: x, y: y)
                drawCutGuide(&sheet, x: x, y: y, width: tile.width, height: tile.height)
            }
        }

        return Sheet(image: sheet, columns: columns, rows: rows, paperSizeInches: paperSizeInches)
    }

    static func blit(_ tile: PixelImage, into sheet: inout PixelImage, atX x0: Int, y y0: Int) {
        for y in 0..<tile.height {
            let destY = y0 + y
            guard destY >= 0, destY < sheet.height else { continue }
            for x in 0..<tile.width {
                let destX = x0 + x
                guard destX >= 0, destX < sheet.width else { continue }
                let source = tile.offset(x: x, y: y)
                let dest = sheet.offset(x: destX, y: destY)
                for c in 0..<4 { sheet.pixels[dest + c] = tile.pixels[source + c] }
            }
        }
    }

    /// Grey guides so the user knows where to cut (LESSONS 14).
    static func drawCutGuide(_ sheet: inout PixelImage, x: Int, y: Int, width: Int, height: Int) {
        let grey: UInt8 = 205
        func set(_ px: Int, _ py: Int) {
            guard px >= 0, px < sheet.width, py >= 0, py < sheet.height else { return }
            let p = sheet.offset(x: px, y: py)
            sheet.pixels[p] = grey
            sheet.pixels[p + 1] = grey
            sheet.pixels[p + 2] = grey
        }
        for px in (x - 1)...(x + width) {
            set(px, y - 1)
            set(px, y + height)
        }
        for py in (y - 1)...(y + height) {
            set(x - 1, py)
            set(x + width, py)
        }
    }
}
