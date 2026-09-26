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
        output: CGImage, jpegSizeKB: Double, spec: DocumentSpec,
        mode: BackgroundMode = .replace
    ) async -> [CheckResult] {
        var checks: [CheckResult] = []
        guard let geometry = SpecGeometry(spec: spec) else { return checks }

        checks.append(dimensionsCheck(output, geometry: geometry))
        if let range = spec.photo.digital.fileSizeKB {
            checks.append(fileSizeCheck(jpegSizeKB, range: range))
        }

        guard let pixels = ImageConversion.pixelImage(from: output) else { return checks }
        let background = RGB(hex: spec.background?.colorHex ?? "#FFFFFF") ?? .white
        checks.append(contentsOf: backgroundChecks(
            pixels, spec: spec, background: background, mode: mode
        ))

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

        // Head height is the rule that matters most, so failing to measure it has to be loud.
        // Skipping it silently let a photo whose cut-out was mangled report "meets requirements"
        // with the single most important check simply absent (LESSONS 18's failure shape).
        let rawMatte = try? await segmenter.matte(for: output)
        let refinedMatte = rawMatte.map {
            MatteRefiner.refine(matte: $0, image: pixels, face: face, tuning: tuning)
        }
        if let refined = refinedMatte {
            let chin = ChinRefiner.refine(luminance: luminance, face: face, tuning: tuning)
            if let crown = CrownFinder.find(matte: refined, face: face, tuning: tuning) {
                checks.append(headHeightCheck(crown: crown, chin: chin, geometry: geometry, spec: spec))
                checks.append(topMarginCheck(crown: crown, geometry: geometry, spec: spec))
            } else {
                checks.append(unmeasuredHeadCheck())
            }
            checks.append(shouldersCheck(refined, spec: spec))
        } else {
            checks.append(unmeasuredHeadCheck())
        }
        checks.append(eyeLineCheck(face, height: pixels.height, geometry: geometry, spec: spec))

        return checks
    }

    /// Reported when the finished photo could not be measured at all. A fail, not a skip: the
    /// user must never be told a photo meets requirements that were never checked.
    func unmeasuredHeadCheck() -> CheckResult {
        CheckResult(
            id: .headHeight, status: .fail,
            measured: "could not be measured in the finished photo",
            requirement: "head height must be verifiable",
            userMessage: "We could not measure the head in the finished photo, so we cannot say it is compliant. Try a photo with more space around the head and a clearer edge between you and the wall."
        )
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
        // The encoder only steps quality DOWN to meet range.max; nothing raises quality or pads
        // to meet range.min. Claiming .automatic on an undersized file promises a fix that no
        // code here can perform.
        let tooSmall = sizeKB < range.min
        return CheckResult(
            id: .fileSize, status: status,
            measured: String(format: "%.0f KB", sizeKB),
            requirement: String(format: "%.0f-%.0f KB", range.min, range.max),
            userMessage: tooSmall && status != .pass
                ? "The finished file is smaller than this document accepts. Use a sharper, higher-resolution photo."
                : nil,
            fixability: tooSmall ? .retakeRequired : .automatic
        )
    }

    func backgroundChecks(
        _ pixels: PixelImage, spec: DocumentSpec, background: RGB,
        mode: BackgroundMode = .replace
    ) -> [CheckResult] {
        let country = spec.country.name
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

        // Purity inside the backdrop region is not enough on its own. When the cut-out fails, the
        // region it finds is SMALL but perfectly pure, so it sails through: on a third-party set,
        // two of three accepted photos kept a rectangular slab of the original background and
        // still scored 99% pure with faceIntegrity passing (LESSONS 8 again). What gives those
        // away is that the space beside the head is not background.
        // `sideMarginPurity` asks whether the space beside the head is our painted colour. That
        // is a cut-out integrity signal (LESSONS 20) and has no meaning when nothing was
        // composited - an unedited photo never contains our colour at all.
        let margins = mode == .replace
            ? sideMarginPurity(pixels, background: background, minimum: UInt8(minimum))
            : 1

        let status = ThresholdEvaluator.evaluateMinimum(fraction, spec.pureFraction)
        let channelOK = darkest >= minimum
        let marginsOK = margins >= 0.9
        let ok = status == .pass && channelOK && marginsOK
        let failed = status == .fail || !channelOK || !marginsOK

        // Without compositing there is no "pure" fraction to speak of: a real wall is never one
        // exact value, so the honest question is whether the wall itself is light enough.
        if mode == .keep {
            let wallOK = darkest >= minimum && total > 0
            let brightness = Int((Double(darkest) / 255 * 100).rounded())
            let needed = Int((Double(minimum) / 255 * 100).rounded())
            return [CheckResult(
                id: .background,
                status: wallOK ? .pass : .fail,
                measured: total > 0
                    ? "your wall reads \(brightness)% brightness at its darkest"
                    : "your wall is too dark to read as a background at all",
                requirement: "at least \(needed)% — effectively white",
                technical: String(
                    format: "darkest channel %d of %d, %.1f%% at the exact colour, region %d px",
                    darkest, minimum, 100 * fraction, total
                ),
                userMessage: wallOK ? nil
                    : "Your own background was kept, so your wall has to pass on its own — and yours is too dark. \(country) needs a wall that is almost pure white, not just light, which most painted walls are not. A white sheet, or a white door in bright even light, is the usual way.",
                // Nothing in processing can fix this: the alternative is an edit the authority
                // has ruled out, which the user is offered separately.
                fixability: .retakeRequired
            )]
        }

        return [CheckResult(
            id: .background,
            status: ok ? .pass : (failed ? .fail : .warn),
            measured: String(format: "%.1f%% pure, darkest channel %d, %.0f%% clear beside the head",
                             100 * fraction, darkest, 100 * margins),
            requirement: String(format: "at least %.0f%% pure, no channel under %d, clear either side",
                                100 * (spec.pureFraction?.failBelow ?? 0.95), minimum),
            userMessage: marginsOK ? nil : "We couldn't separate you from the background cleanly. Try a photo taken against a plain, light wall.",
            fixability: .automatic
        )]
    }

    /// How much of the narrow strip down each side, level with the head, is background.
    ///
    /// A correctly framed passport photo always has clear space either side of the head at eye
    /// level. A mangled cut-out does not, which is what catches a matte that kept a slab of the
    /// original photo even though everything it did keep is the right colour.
    func sideMarginPurity(_ pixels: PixelImage, background: RGB, minimum: UInt8) -> Double {
        let width = pixels.width, height = pixels.height
        guard width > 20, height > 20 else { return 1 }

        let strip = max(1, width / 14)
        let top = Int(Double(height) * 0.25)
        let bottom = Int(Double(height) * 0.55)
        guard bottom > top else { return 1 }

        var clear = 0, total = 0
        for y in top..<bottom {
            for x in 0..<strip {
                for column in [x, width - 1 - x] {
                    let p = pixels.offset(x: column, y: y)
                    let darkest = min(pixels.pixels[p], min(pixels.pixels[p + 1], pixels.pixels[p + 2]))
                    total += 1
                    if darkest >= minimum { clear += 1 }
                }
            }
        }
        return total > 0 ? Double(clear) / Double(total) : 1
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
        // No authority in the set publishes an eye-line position: GOV.UK, canada.ca, the EU
        // Commission guidance and the Warsaw consulate page all state none, and the US spec says
        // so outright. The bands are ours, derived to place a head sensibly - useful guidance,
        // but not a rule anyone can be failed against. A fail here rejected photos the authority
        // would accept, and for India the band is not even reachable for every face given the
        // top-margin band, which made it an unfixable fail.
        let measured = ThresholdEvaluator.evaluateRange(fromBottom, band)
        let status: CheckStatus = measured == .fail ? .warn : measured
        return CheckResult(
            id: .eyeLine, status: status,
            measured: String(format: "%.1f%% up from the bottom", 100 * fromBottom),
            requirement: band.map { String(format: "%.0f-%.0f%% (our guide, not a stated rule)", 100 * $0.min, 100 * $0.max) } ?? "any",
            userMessage: status == .warn
                ? "The eyes sit outside where we aim to place them. No authority here publishes an eye-line rule, so this is guidance rather than a requirement."
                : nil,
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
