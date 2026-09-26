import Foundation

public enum Units {
    public static let mmPerInch = 25.4

    public static func mmToPx(_ mm: Double, dpi: Double) -> Double { mm / mmPerInch * dpi }
    public static func pxToMM(_ px: Double, dpi: Double) -> Double { px * mmPerInch / dpi }
}

/// Values derived from a spec's photo geometry.
///
/// `pxPerMM` comes from the digital pixel size divided by the physical size, **not** from
/// `photo.digital.dpi`. For in-passport those disagree: 630x810 px at 35x45 mm is ~457 dpi,
/// while `dpi: 300` describes the print tiles (413x531 px). Using dpi here would compute a
/// head height ~34% too small and silently fail every head-size check.
public struct SpecGeometry: Sendable, Equatable {
    public let outputSizePx: Size
    public let photoSizeMM: Size
    public let pxPerMM: Double
    /// Minimum chin-to-crown height, in source pixels, that the output needs. Below this the
    /// photo must be rejected rather than upscaled (LESSONS 3).
    public let requiredHeadPx: Double

    public init?(spec: DocumentSpec) {
        guard let outputSizePx = spec.photo.digital.outputSizePx else { return nil }
        let photoSizeMM = spec.photo.sizeMM
        guard photoSizeMM.height > 0, outputSizePx.height > 0 else { return nil }

        self.outputSizePx = outputSizePx
        self.photoSizeMM = photoSizeMM
        self.pxPerMM = outputSizePx.height / photoSizeMM.height

        let head = spec.geometry.headHeight
        let targetMM = head.targetMM
            ?? head.passMM?.min
            ?? head.passFraction.map { $0.min * photoSizeMM.height }
        self.requiredHeadPx = (targetMM ?? 0) * pxPerMM
    }

    /// The digital file's true density, for the JPEG's DPI metadata. Stamping
    /// `photo.print.dpi` there would be a lie: 630x810 at 35x45 mm is 457 ppi, so a lab that
    /// honours the embedded value would print it 52% too large.
    public var digitalDPI: Double { pxPerMM * Units.mmPerInch }

    public func mmToPx(_ mm: Double) -> Double { mm * pxPerMM }
    public func pxToMM(_ px: Double) -> Double { px / pxPerMM }

    /// Pixel size of one print tile at the spec's print dpi (35x45 mm at 300 dpi -> 413x531).
    public static func printTilePx(spec: DocumentSpec) -> Size {
        let dpi = spec.photo.print.dpi
        return Size(
            width: (Units.mmToPx(spec.photo.sizeMM.width, dpi: dpi)).rounded(),
            height: (Units.mmToPx(spec.photo.sizeMM.height, dpi: dpi)).rounded()
        )
    }
}
