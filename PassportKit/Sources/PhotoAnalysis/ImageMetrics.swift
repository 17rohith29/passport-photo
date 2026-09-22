import CoreGraphics
import Foundation

/// Pure measurements on pixels. No Vision, no Core Image, so these are testable on synthetic input.
public enum ImageMetrics {

    /// Laplacian variance over the face box, resampled to a fixed size so photos of different
    /// resolution compare fairly (reference/python/auto_passport.py normalises to 256 px).
    public static func sharpness(luminance: GrayImage, faceBox: CGRect, normalizedTo side: Int = 256) -> Double {
        let box = clamp(faceBox, width: luminance.width, height: luminance.height)
        guard box.width > 2, box.height > 2 else { return 0 }
        let roi = luminance.cropped(to: box).resized(width: side, height: side)
        return laplacianVariance(roi)
    }

    /// Laplacian variance over an explicit region, at native resolution. Used for the eye-region
    /// sharpness check on the finished output, where the size is already fixed by the spec.
    public static func sharpness(luminance: GrayImage, region: CGRect) -> Double {
        let box = clamp(region, width: luminance.width, height: luminance.height)
        guard box.width > 2, box.height > 2 else { return 0 }
        return laplacianVariance(luminance.cropped(to: box))
    }

    static func laplacianVariance(_ image: GrayImage) -> Double {
        guard image.width > 2, image.height > 2 else { return 0 }
        var values: [Double] = []
        values.reserveCapacity((image.width - 2) * (image.height - 2))
        for y in 1..<(image.height - 1) {
            for x in 1..<(image.width - 1) {
                let laplacian = -4 * image[x, y]
                    + image[x - 1, y] + image[x + 1, y]
                    + image[x, y - 1] + image[x, y + 1]
                values.append(Double(laplacian))
            }
        }
        return variance(values)
    }

    /// Brightness difference between the two cheeks, as a fraction of the brighter one.
    ///
    /// LESSONS 5: this metric is fragile — the same photo scored 2% or 11% under two patch
    /// placements. The placement is therefore fixed by `Tuning` and calibrated on fixtures,
    /// and the result feeds a warn band rather than a single hard limit.
    public static func cheekImbalance(
        luminance: GrayImage, face: FaceMeasurements, tuning: Tuning = .default
    ) -> Double {
        let faceWidth = Double(face.faceWidth)
        guard faceWidth > 0 else { return 0 }

        // Two small patches are far too sensitive to what they happen to land on: with one patch
        // on beard and one on skin, IMG_0012 read 13.3% against the reference's 8.9%, and ranked
        // *worse* than the genuinely side-lit IMG_0010. Instead take the median over a whole
        // cheek region on each side. The median ignores beard, stray shadow and specular
        // highlights, which is what made the patch version swing (LESSONS 5).
        let eyeY = Double(face.eyeMidpoint.y)
        let chinY = Double(face.rawChin.y)
        let midlineX = Double(face.eyeMidpoint.x)
        guard eyeY.isFinite, chinY.isFinite, midlineX.isFinite, faceWidth.isFinite else { return 0 }

        // Below the eye sockets, above the chin: the cheeks.
        let top = eyeY + tuning.cheekRegionTop * (chinY - eyeY)
        let bottom = eyeY + tuning.cheekRegionBottom * (chinY - eyeY)
        guard top.isFinite, bottom.isFinite, bottom > top else { return 0 }

        // Sideways the region is bounded by the contour *at each row*, inset from the silhouette.
        // A fixed fraction of the overall face width reaches past the cheek onto hair, ears and
        // background where the face narrows, which read 0.000 on IMG_0015 and 0.178 on IMG_0009
        // against reference values of 0.072 and 0.043.
        let yStart = max(0, Int(top.rounded()))
        let yEnd = min(luminance.height - 1, Int(bottom.rounded()))
        guard yEnd > yStart else { return 0 }

        var left: [Float] = []
        var right: [Float] = []
        let step = max(1, (yEnd - yStart) / 60)

        for y in stride(from: yStart, through: yEnd, by: step) {
            let (edgeLeft, edgeRight) = contourEdges(face: face, atY: Double(y))
            let rowHalfWidth = (edgeRight - edgeLeft) / 2
            guard rowHalfWidth.isFinite, rowHalfWidth > 4 else { continue }

            let inner = tuning.cheekRegionInner * rowHalfWidth
            let margin = tuning.cheekRegionEdgeInset * rowHalfWidth
            let lowerBound = max(0, Int((edgeLeft + margin).rounded()))
            let upperBound = min(luminance.width - 1, Int((edgeRight - margin).rounded()))
            guard upperBound > lowerBound else { continue }

            for x in stride(from: lowerBound, through: upperBound, by: step) {
                let offset = Double(x) - midlineX
                guard abs(offset) >= inner else { continue }
                let value = luminance.at(x: x, y: y)
                if offset < 0 { left.append(value) } else { right.append(value) }
            }
        }
        guard !left.isEmpty, !right.isEmpty else { return 0 }

        let leftMedian = Double(median(left))
        let rightMedian = Double(median(right))
        let brighter = max(leftMedian, rightMedian)
        guard brighter > 0 else { return 0 }
        return abs(leftMedian - rightMedian) / brighter
    }

    static func median(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count % 2 == 1 { return sorted[middle] }
        return (sorted[middle - 1] + sorted[middle]) / 2
    }

    /// Leftmost and rightmost contour points near a given height, widening the search band until
    /// some are found.
    static func contourEdges(face: FaceMeasurements, atY y: Double) -> (Double, Double) {
        let faceHeight = max(1.0, Double(face.rawChin.y) - Double(face.browY))
        for fraction in [0.08, 0.15, 0.25, 0.5] {
            let band = fraction * faceHeight
            let nearby = face.contour.filter { abs(Double($0.y) - y) < band }
            if let minX = nearby.map({ Double($0.x) }).min(),
               let maxX = nearby.map({ Double($0.x) }).max(), maxX > minX {
                return (minX, maxX)
            }
        }
        return (Double(face.contourMinX), Double(face.contourMaxX))
    }

    static func meanPatch(_ image: GrayImage, centreX: Double, centreY: Double, radius: Double) -> Double {
        guard centreX.isFinite, centreY.isFinite, radius.isFinite, radius >= 0 else { return 0 }
        let r = Int(min(radius, 4096).rounded())
        let cx = Int(min(max(centreX, -1e6), 1e6).rounded())
        let cy = Int(min(max(centreY, -1e6), 1e6).rounded())
        var total = 0.0
        var count = 0
        for y in (cy - r)...(cy + r) {
            for x in (cx - r)...(cx + r) {
                total += Double(image.at(x: x, y: y))
                count += 1
            }
        }
        return count > 0 ? total / Double(count) : 0
    }

    static func variance(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let sum = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        return sum / Double(values.count)
    }

    /// Clamps a region to the image. Non-finite input returns an empty rect rather than reaching
    /// `Int(_:)`, which traps on NaN and on infinity — a face whose landmarks collapse to a point
    /// divides by a zero width and produces exactly that.
    static func clamp(_ rect: CGRect, width: Int, height: Int) -> CGRect {
        guard rect.minX.isFinite, rect.minY.isFinite,
              rect.maxX.isFinite, rect.maxY.isFinite else { return .zero }
        let limit = CGFloat(Int.max / 4)
        guard abs(rect.minX) < limit, abs(rect.minY) < limit,
              abs(rect.maxX) < limit, abs(rect.maxY) < limit else { return .zero }

        let x0 = max(0, Int(rect.minX.rounded(.down)))
        let y0 = max(0, Int(rect.minY.rounded(.down)))
        let x1 = min(width, Int(rect.maxX.rounded(.up)))
        let y1 = min(height, Int(rect.maxY.rounded(.up)))
        return CGRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }
}
