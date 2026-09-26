import CoreGraphics
import Foundation

/// Cleans up a raw segmentation mask.
///
/// Closed-form matting from the reference pipeline is too slow on device, so this keeps the parts
/// that mattered: fill interior holes **before** any edge work (LESSONS 8 — a seam along the
/// eyebrows let rim cleanup paint a white streak across the brows while every metric passed),
/// clean only the outer rim (LESSONS 7), and vary the band width with height (LESSONS 9).
public enum MatteRefiner {

    public static func refine(
        matte: AlphaMatte, image: PixelImage, face: FaceMeasurements, tuning: Tuning = .default
    ) -> AlphaMatte {
        // A zero width or height makes the border scans index row -1 (LESSONS 24). Vision's
        // mattes are always resized to the image, but the segmenter is injectable.
        guard matte.width > 0, matte.height > 0,
              matte.values.count == matte.width * matte.height else { return matte }
        var hard = largestComponent(matte)
        fillHoles(&hard, width: matte.width, height: matte.height)
        let distance = signedDistance(hard, width: matte.width, height: matte.height)
        var refined = softEdges(matte: matte, hard: hard, distance: distance, face: face, tuning: tuning)
        cleanRim(&refined, image: image, distance: distance, face: face, tuning: tuning)
        refined = blur(refined, radius: 1)
        return rescale(refined, tuning: tuning)
    }

    /// Keeps the biggest connected blob, dropping wall fragments that survived segmentation.
    static func largestComponent(_ matte: AlphaMatte) -> [Bool] {
        let width = matte.width, height = matte.height
        var inside = [Bool](repeating: false, count: width * height)
        for i in matte.values.indices { inside[i] = matte.values[i] > 0.5 }

        var label = [Int32](repeating: 0, count: width * height)
        var best = 0, bestSize = 0, next: Int32 = 0
        var stack: [Int] = []

        for start in 0..<(width * height) where inside[start] && label[start] == 0 {
            next += 1
            var size = 0
            stack.append(start)
            label[start] = next
            while let index = stack.popLast() {
                size += 1
                let x = index % width, y = index / width
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    let neighbour = ny * width + nx
                    if inside[neighbour] && label[neighbour] == 0 {
                        label[neighbour] = next
                        stack.append(neighbour)
                    }
                }
            }
            if size > bestSize { bestSize = size; best = Int(next) }
        }

        return label.map { $0 == Int32(best) && best > 0 }
    }

    /// Flood fill from the border: anything not reached is interior and becomes subject.
    static func fillHoles(_ mask: inout [Bool], width: Int, height: Int) {
        var outside = [Bool](repeating: false, count: mask.count)
        var stack: [Int] = []
        for x in 0..<width {
            for y in [0, height - 1] {
                let i = y * width + x
                if !mask[i] && !outside[i] { outside[i] = true; stack.append(i) }
            }
        }
        for y in 0..<height {
            for x in [0, width - 1] {
                let i = y * width + x
                if !mask[i] && !outside[i] { outside[i] = true; stack.append(i) }
            }
        }
        while let index = stack.popLast() {
            let x = index % width, y = index / width
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                let neighbour = ny * width + nx
                if !mask[neighbour] && !outside[neighbour] {
                    outside[neighbour] = true
                    stack.append(neighbour)
                }
            }
        }
        for i in mask.indices where !mask[i] && !outside[i] { mask[i] = true }
    }

    /// Distance to the nearest edge, positive inside, negative outside. Two-pass chamfer.
    static func signedDistance(_ mask: [Bool], width: Int, height: Int) -> [Float] {
        var distance = [Float](repeating: 0, count: mask.count)
        var inside = [Float](repeating: Float.greatestFiniteMagnitude, count: mask.count)
        var outside = [Float](repeating: Float.greatestFiniteMagnitude, count: mask.count)

        for i in mask.indices {
            let x = i % width, y = i / width
            var edge = false
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                if mask[ny * width + nx] != mask[i] { edge = true; break }
            }
            if edge { inside[i] = 0; outside[i] = 0 }
        }

        chamfer(&inside, width: width, height: height)
        chamfer(&outside, width: width, height: height)
        for i in mask.indices {
            distance[i] = mask[i] ? inside[i] : -outside[i]
        }
        return distance
    }

    private static func chamfer(_ field: inout [Float], width: Int, height: Int) {
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                if x > 0 { field[i] = min(field[i], field[i - 1] + 1) }
                if y > 0 { field[i] = min(field[i], field[i - width] + 1) }
                if x > 0 && y > 0 { field[i] = min(field[i], field[i - width - 1] + 1.4142) }
            }
        }
        for y in stride(from: height - 1, through: 0, by: -1) {
            for x in stride(from: width - 1, through: 0, by: -1) {
                let i = y * width + x
                if x < width - 1 { field[i] = min(field[i], field[i + 1] + 1) }
                if y < height - 1 { field[i] = min(field[i], field[i + width] + 1) }
                if x < width - 1 && y < height - 1 { field[i] = min(field[i], field[i + width + 1] + 1.4142) }
            }
        }
    }

    /// Band width varies with y: wide above the brow (hair), narrow below (skin, shirt).
    static func bandWidth(
        y: Int, face: FaceMeasurements, imageSize: Double, tuning: Tuning
    ) -> Float {
        let scale = imageSize / tuning.bandReferenceSize
        let brow = Double(face.browY)
        let faceHeight = max(1.0, Double(face.rawChin.y) - brow)
        var t = (Double(y) - brow) / (tuning.bandTransition * faceHeight)
        t = min(max(t, 0), 1)
        t = t * t * (3 - 2 * t)
        return Float((1 - t) * tuning.bandWidthHair * scale + t * tuning.bandWidthSkin * scale)
    }

    static func softEdges(
        matte: AlphaMatte, hard: [Bool], distance: [Float],
        face: FaceMeasurements, tuning: Tuning
    ) -> AlphaMatte {
        var out = GrayImage(width: matte.width, height: matte.height)
        let imageSize = Double(max(matte.width, matte.height))
        for y in 0..<matte.height {
            let band = bandWidth(y: y, face: face, imageSize: imageSize, tuning: tuning)
            for x in 0..<matte.width {
                let i = y * matte.width + x
                let d = distance[i]
                if d > band {
                    out.values[i] = 1
                } else if d < -band {
                    out.values[i] = 0
                } else {
                    // Inside the band, keep the network's own soft alpha but anchor it to the
                    // cleaned hard mask so filled holes stay filled.
                    let ramp = (d + band) / (2 * band)
                    out.values[i] = max(0, min(1, 0.5 * matte.values[i] + 0.5 * ramp))
                }
            }
        }
        return out
    }

    /// Wall residue sits on the rim only: low saturation, bright, near the edge, never in the core.
    static func cleanRim(
        _ matte: inout AlphaMatte, image: PixelImage, distance: [Float],
        face: FaceMeasurements, tuning: Tuning
    ) {
        let imageSize = Double(max(matte.width, matte.height))
        for y in 0..<matte.height {
            let band = bandWidth(y: y, face: face, imageSize: imageSize, tuning: tuning)
            for x in 0..<matte.width {
                let i = y * matte.width + x
                let d = distance[i]
                guard d <= band + 2, d > -band - 2 else { continue }
                // Never touch the silhouette core (LESSONS 7/8).
                guard d < band * 0.5 else { continue }
                let p = i * 4
                guard p + 2 < image.pixels.count else { continue }
                let r = Float(image.pixels[p]) / 255
                let g = Float(image.pixels[p + 1]) / 255
                let b = Float(image.pixels[p + 2]) / 255
                guard looksLikeBackdrop(image, index: i, tuning: tuning) else { continue }
                // Near the face, behave exactly as before: rim cleanup around skin is tuned and
                // LESSONS 21 records what happens when it is disturbed. The coherence rule below
                // applies only where the defect is - hair, above the brows or beyond the sides
                // of the face - so face behaviour cannot change.
                guard isHairRegion(x: x, y: y, face: face) else {
                    matte.values[i] = 0
                    continue
                }
                // Backdrop is a REGION, not a stray pixel. A highlight on a strand of hair is
                // bright and low-saturation too, but it sits among dark neighbours, while wall
                // is surrounded by more wall. Without this, every sheen on dark hair was cleared
                // and the crown came out speckled with backdrop colour (LESSONS 37).
                var backdropNeighbours = 0
                var sampled = 0
                let reach = tuning.rimCoherenceReach
                for dy in [-reach, 0, reach] {
                    for dx in [-reach, 0, reach] where dx != 0 || dy != 0 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, nx < matte.width, ny >= 0, ny < matte.height else { continue }
                        sampled += 1
                        if looksLikeBackdrop(image, index: ny * matte.width + nx, tuning: tuning) {
                            backdropNeighbours += 1
                        }
                    }
                }
                guard sampled > 0 else { continue }
                let agreement = Double(backdropNeighbours) / Double(sampled)
                if agreement >= tuning.rimCoherenceFraction {
                    matte.values[i] = 0
                }
            }
        }
    }

    /// Hair rather than face: above the brow line, or clear of the sides of the face contour.
    static func isHairRegion(x: Int, y: Int, face: FaceMeasurements) -> Bool {
        let browY = Double(face.browY)
        let minX = Double(face.contourMinX), maxX = Double(face.contourMaxX)
        let faceWidth = Double(face.faceWidth)
        guard browY.isFinite, abs(browY) < 1e6, minX.isFinite, maxX.isFinite,
              abs(minX) < 1e6, abs(maxX) < 1e6, faceWidth.isFinite, faceWidth > 1
        else { return false }
        let margin = 0.08 * faceWidth
        return Double(y) < browY || Double(x) < minX - margin || Double(x) > maxX + margin
    }

    /// The colour test rim cleanup uses: bright and close to grey. Unchanged from LESSONS 7 -
    /// deliberately NOT a distance to this photo's wall colour, which LESSONS 21 records as
    /// having wiped a face twice.
    static func looksLikeBackdrop(_ image: PixelImage, index: Int, tuning: Tuning) -> Bool {
        let p = index * 4
        guard p + 2 < image.pixels.count else { return false }
        let r = Float(image.pixels[p]) / 255
        let g = Float(image.pixels[p + 1]) / 255
        let b = Float(image.pixels[p + 2]) / 255
        let value = max(r, max(g, b))
        let minimum = min(r, min(g, b))
        let saturation = value > 0 ? (value - minimum) / value : 0
        return saturation < tuning.rimMaxSaturation && value > tuning.rimMinValue
    }

    static func blur(_ image: GrayImage, radius: Int) -> GrayImage {
        guard radius > 0 else { return image }
        var horizontal = GrayImage(width: image.width, height: image.height)
        for y in 0..<image.height {
            for x in 0..<image.width {
                var sum: Float = 0
                var count: Float = 0
                for dx in -radius...radius {
                    sum += image.at(x: x + dx, y: y); count += 1
                }
                horizontal[x, y] = sum / count
            }
        }
        var out = GrayImage(width: image.width, height: image.height)
        for y in 0..<image.height {
            for x in 0..<image.width {
                var sum: Float = 0
                var count: Float = 0
                for dy in -radius...radius {
                    sum += horizontal.at(x: x, y: y + dy); count += 1
                }
                out[x, y] = sum / count
            }
        }
        return out
    }

    static func rescale(_ matte: AlphaMatte, tuning: Tuning) -> AlphaMatte {
        var out = matte
        for i in out.values.indices {
            out.values[i] = min(max((out.values[i] - tuning.matteFloor) / tuning.matteScale, 0), 1)
        }
        return out
    }
}
