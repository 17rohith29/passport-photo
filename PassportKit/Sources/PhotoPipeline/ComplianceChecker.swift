import CoreGraphics
import Foundation
import PhotoAnalysis
import SpecKit

/// Measures the finished photo from scratch.
///
/// LESSONS 13: a validator that reuses the planner's numbers cannot find the planner's mistakes,
/// so this re-runs face analysis and crown/chin detection on the output image.
public struct ComplianceChecker: Sendable {

    public var analyzer: any FaceAnalyzing
    public var segmenter: any SubjectSegmenting
    public var tuning: Tuning

    public init(
        analyzer: any FaceAnalyzing = VisionFaceAnalyzer(),
        segmenter: any SubjectSegmenting = VisionSubjectSegmenter(),
        tuning: Tuning = .default
    ) {
        self.analyzer = analyzer
        self.segmenter = segmenter
        self.tuning = tuning
    }

    public func check(
        output: CGImage, jpegSizeKB: Double, spec: DocumentSpec
    ) async -> [CheckResult] {
        var checks: [CheckResult] = []
        guard let geometry = SpecGeometry(spec: spec) else { return checks }

        checks.append(dimensionsCheck(output, geometry: geometry))
        if let range = spec.photo.digital.fileSizeKB {
            checks.append(fileSizeCheck(jpegSizeKB, range: range))
        }

        guard let pixels = ImageConversion.pixelImage(from: output) else { return checks }
        let background = RGB(hex: spec.background?.colorHex ?? "#FFFFFF") ?? .white
        checks.append(contentsOf: backgroundChecks(pixels, spec: spec, background: background))

        guard let face = try? await analyzer.analyze(output) else {
            checks.append(CheckResult(
                id: .faceCount, status: .fail,
                measured: "no face found in the finished photo",
                requirement: "exactly one face",
                userMessage: "Something went wrong while processing. Try another photo."
            ))
            return checks
        }

        let luminance = ImageConversion.luminance(of: pixels)
        checks.append(rollCheck(face, spec: spec))
        checks.append(centeringCheck(face, width: pixels.width, spec: spec))
        checks.append(faceIntegrityCheck(pixels, face: face))

        if let matte = try? await segmenter.matte(for: output) {
            let refined = MatteRefiner.refine(matte: matte, image: pixels, face: face, tuning: tuning)
            let chin = ChinRefiner.refine(luminance: luminance, face: face, tuning: tuning)
            if let crown = CrownFinder.find(matte: refined, face: face, tuning: tuning) {
                checks.append(headHeightCheck(crown: crown, chin: chin, geometry: geometry, spec: spec))
                checks.append(topMarginCheck(crown: crown, geometry: geometry, spec: spec))
            }
            checks.append(shouldersCheck(refined, spec: spec))
        }
        checks.append(eyeLineCheck(face, height: pixels.height, geometry: geometry, spec: spec))

        return checks
    }

    func dimensionsCheck(_ image: CGImage, geometry: SpecGeometry) -> CheckResult {
        let expected = geometry.outputSizePx
        let ok = image.width == Int(expected.width) && image.height == Int(expected.height)
        return CheckResult(
            id: .dimensions, status: ok ? .pass : .fail,
            measured: "\(image.width)x\(image.height) px",
            requirement: "\(Int(expected.width))x\(Int(expected.height)) px",
            fixability: .automatic
        )
    }

    func fileSizeCheck(_ sizeKB: Double, range: SpecKit.Range) -> CheckResult {
        let status = ThresholdEvaluator.evaluateRange(sizeKB, range)
        return CheckResult(
            id: .fileSize, status: status,
            measured: String(format: "%.0f KB", sizeKB),
            requirement: String(format: "%.0f-%.0f KB", range.min, range.max),
            fixability: .automatic
        )
    }

    func backgroundChecks(_ pixels: PixelImage, spec: DocumentSpec, background: RGB) -> [CheckResult] {
        guard let spec = spec.background else { return [] }
        let minimum = spec.minChannelValue ?? 245
        let (br, bg, bb) = background.bytes

        // The backdrop is the light region connected to the top corners, not the outer frame:
        // the bottom edge is legitimately shoulders, and framing the whole border measured the
        // shirt as failed background (76.3% pure, darkest channel 0 on the golden case).
        let region = backdropRegion(pixels, minimum: UInt8(minimum))
        var pure = 0, total = 0
        var darkest = 255
        for i in 0..<(pixels.width * pixels.height) where region[i] {
            total += 1
            let p = i * 4
            if pixels.pixels[p] == br, pixels.pixels[p + 1] == bg, pixels.pixels[p + 2] == bb {
                pure += 1
            }
            darkest = min(darkest, Int(min(pixels.pixels[p], min(pixels.pixels[p + 1], pixels.pixels[p + 2]))))
        }
        let fraction = total > 0 ? Double(pure) / Double(total) : 0

        let status = ThresholdEvaluator.evaluateMinimum(fraction, spec.pureFraction)
        let channelOK = darkest >= minimum
        return [CheckResult(
            id: .background,
            status: (status == .pass && channelOK) ? .pass : (status == .fail || !channelOK ? .fail : .warn),
            measured: String(format: "%.1f%% pure, darkest channel %d", 100 * fraction, darkest),
            requirement: String(format: "at least %.0f%% pure, no channel under %d",
                                100 * (spec.pureFraction?.failBelow ?? 0.95), minimum),
            fixability: .automatic
        )]
    }

    /// Light pixels reachable from the top corners. Mirrors the reference pipeline, which takes
    /// the connected white component containing the top-left pixel.
    func backdropRegion(_ pixels: PixelImage, minimum: UInt8) -> [Bool] {
        let width = pixels.width, height = pixels.height
        var light = [Bool](repeating: false, count: width * height)
        for i in 0..<(width * height) {
            let p = i * 4
            let darkest = min(pixels.pixels[p], min(pixels.pixels[p + 1], pixels.pixels[p + 2]))
            light[i] = darkest >= minimum
        }

        var region = [Bool](repeating: false, count: width * height)
        var stack: [Int] = []
        for corner in [0, width - 1] where light[corner] {
            region[corner] = true
            stack.append(corner)
        }
        while let index = stack.popLast() {
            let x = index % width, y = index / width
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                let neighbour = ny * width + nx
                if light[neighbour] && !region[neighbour] {
                    region[neighbour] = true
                    stack.append(neighbour)
                }
            }
        }
        return region
    }

    func rollCheck(_ face: FaceMeasurements, spec: DocumentSpec) -> CheckResult {
        let value = abs(face.eyeLineAngleDeg)
        let limit = spec.pose?.rollDeg?.outputFailAbove
        let status: CheckStatus = limit.map { value > $0 ? .fail : .pass } ?? .pass
        return CheckResult(
            id: .roll, status: status,
            measured: String(format: "%.2f°", value),
            requirement: limit.map { String(format: "under %.0f°", $0) } ?? "any",
            fixability: .automatic
        )
    }

    func centeringCheck(_ face: FaceMeasurements, width: Int, spec: DocumentSpec) -> CheckResult {
        let offset = abs(Double(face.eyeMidpoint.x) - Double(width) / 2) / Double(width)
        let status = ThresholdEvaluator.evaluateMaximum(offset, spec.geometry.horizontalOffsetFraction)
        return CheckResult(
            id: .centering, status: status,
            measured: String(format: "%.2f%% off centre", 100 * offset),
            requirement: spec.geometry.horizontalOffsetFraction?.failAbove
                .map { String(format: "under %.0f%%", 100 * $0) } ?? "any",
            fixability: .automatic
        )
    }

    /// Public so the head-height rule can be exercised directly, whichever way a spec states it.
    public func headHeightCheck(
        crown: CGFloat, chin: CGFloat, geometry: SpecGeometry, spec: DocumentSpec
    ) -> CheckResult {
        let mm = geometry.pxToMM(Double(chin - crown))
        // A spec may state the head as millimetres or as a fraction of the photo height. The EU
        // states only a fraction ("70-80% of the photograph"), and reading passMM alone silently
        // skipped the check entirely for such a spec.
        let band = HeadHeightBand.inMM(spec: spec)
        let status = ThresholdEvaluator.evaluateRange(mm, band)
        return CheckResult(
            id: .headHeight, status: status,
            measured: String(format: "%.2f mm chin to crown", mm),
            requirement: band.map { String(format: "%.2f-%.2f mm", $0.min, $0.max) } ?? "any",
            fixability: .automatic
        )
    }

    func topMarginCheck(crown: CGFloat, geometry: SpecGeometry, spec: DocumentSpec) -> CheckResult {
        let mm = geometry.pxToMM(Double(crown))
        let band = spec.geometry.topMargin?.passMM
        let status = ThresholdEvaluator.evaluateRange(mm, band)
        return CheckResult(
            id: .topMargin, status: status,
            measured: String(format: "%.2f mm above the head", mm),
            requirement: band.map { String(format: "%.1f-%.1f mm", $0.min, $0.max) } ?? "any",
            fixability: .automatic
        )
    }

    func eyeLineCheck(
        _ face: FaceMeasurements, height: Int, geometry: SpecGeometry, spec: DocumentSpec
    ) -> CheckResult {
        let fromBottom = (Double(height) - Double(face.eyeMidpoint.y)) / Double(height)
        let band = CropPlanner.eyeLineBand(spec: spec, photoHeightMM: spec.photo.sizeMM.height)
        let status = ThresholdEvaluator.evaluateRange(fromBottom, band)
        return CheckResult(
            id: .eyeLine, status: status,
            measured: String(format: "%.1f%% up from the bottom", 100 * fromBottom),
            requirement: band.map { String(format: "%.0f-%.0f%%", 100 * $0.min, 100 * $0.max) } ?? "any",
            fixability: .automatic
        )
    }

    /// LESSONS 8: a mask seam let rim cleanup paint a white streak across the eyebrows while
    /// every other metric passed. Nothing inside the face may be turned near-white.
    func faceIntegrityCheck(_ pixels: PixelImage, face: FaceMeasurements) -> CheckResult {
        let minX = Double(face.contourMinX), maxX = Double(face.contourMaxX)
        let centreX = (minX + maxX) / 2
        let radiusX = (maxX - minX) / 2 * 0.75
        let topY = Double(face.browY)
        let bottomY = Double(face.rawChin.y)
        let centreY = (topY + bottomY) / 2
        let radiusY = (bottomY - topY) / 2 * 0.85
        guard radiusX > 1, radiusY > 1 else {
            return CheckResult(
                id: .faceIntegrity, status: .warn,
                measured: "face region too small to check", requirement: "no white patches on the face"
            )
        }

        var whitened = 0, total = 0
        let x0 = max(0, Int(centreX - radiusX)), x1 = min(pixels.width - 1, Int(centreX + radiusX))
        let y0 = max(0, Int(centreY - radiusY)), y1 = min(pixels.height - 1, Int(centreY + radiusY))
        guard x1 > x0, y1 > y0 else {
            return CheckResult(
                id: .faceIntegrity, status: .warn,
                measured: "face region off image", requirement: "no white patches on the face"
            )
        }

        for y in y0...y1 {
            for x in x0...x1 {
                let nx = (Double(x) - centreX) / radiusX
                let ny = (Double(y) - centreY) / radiusY
                guard nx * nx + ny * ny <= 1 else { continue }
                total += 1
                let p = pixels.offset(x: x, y: y)
                let darkest = min(pixels.pixels[p], min(pixels.pixels[p + 1], pixels.pixels[p + 2]))
                if darkest >= tuning.faceWhiteThreshold { whitened += 1 }
            }
        }
        let fraction = total > 0 ? Double(whitened) / Double(total) : 0
        let ok = fraction <= tuning.maxFaceWhitened
        return CheckResult(
            id: .faceIntegrity, status: ok ? .pass : .fail,
            measured: String(format: "%.2f%% of the face is near-white", 100 * fraction),
            requirement: String(format: "under %.1f%%", 100 * tuning.maxFaceWhitened),
            userMessage: ok ? nil : "Processing damaged the face. Try another photo.",
            fixability: .automatic
        )
    }

    func shouldersCheck(_ matte: AlphaMatte, spec: DocumentSpec) -> CheckResult {
        let y = matte.height - 1
        var minX = matte.width, maxX = -1
        for x in 0..<matte.width where matte[x, y] > 0.5 {
            minX = min(minX, x)
            maxX = max(maxX, x)
        }
        let span = maxX >= minX ? Double(maxX - minX) / Double(matte.width) : 0
        let status = ThresholdEvaluator.evaluateMinimum(span, spec.geometry.shouldersVisibleFraction)
        return CheckResult(
            id: .shouldersVisible, status: status,
            measured: String(format: "%.0f%% of the width at the bottom edge", 100 * span),
            requirement: spec.geometry.shouldersVisibleFraction?.failBelow
                .map { String(format: "at least %.0f%%", 100 * $0) } ?? "any",
            userMessage: status == .pass ? nil : "Your shoulders need to be in the photo.",
            fixability: .retakeRequired
        )
    }
}
