import Foundation

/// A non-fatal problem with a spec: it loads and is usable, but something in it is misleading
/// enough to burn whoever reads it next. Kept separate from `validate()`, which throws on specs
/// that cannot be used at all.
public struct SpecAdvisory: Sendable, Equatable, Identifiable {
    public var field: String
    public var message: String
    public var id: String { field }
}

public extension DocumentSpec {
    /// Advisories are surfaced to whoever edits `specs/`, not to users.
    var advisories: [SpecAdvisory] {
        var found: [SpecAdvisory] = []

        // photo.digital.dpi is metadata stamped into the exported JPEG, not a geometry input.
        // When it disagrees with the pixel size, say so: deriving px-per-mm from dpi is the
        // single easiest way to get every head measurement wrong (see docs/PROGRESS.md, M1).
        if let stated = photo.digital.dpi,
           let size = photo.digital.outputSizePx,
           photo.sizeMM.height > 0, stated > 0 {
            let implied = size.height / (photo.sizeMM.height / Units.mmPerInch)
            if abs(implied - stated) / stated > 0.02 {
                found.append(SpecAdvisory(
                    field: "photo.digital.dpi",
                    message: """
                    states \(Self.trim(stated)) dpi, but \(Self.trim(size.width))x\(Self.trim(size.height)) px \
                    at \(Self.trim(photo.sizeMM.width))x\(Self.trim(photo.sizeMM.height)) mm implies \
                    \(Self.trim(implied.rounded())) dpi. This field is export metadata only; geometry uses \
                    the pixel size (\(Self.trim(size.height / photo.sizeMM.height)) px/mm).
                    """
                ))
            }
        }

        if geometry.headHeight.targetMM == nil {
            found.append(SpecAdvisory(
                field: "geometry.headHeight.targetMM",
                message: "no target: the planner falls back to the bottom of the pass band, which sits on a limit rather than in the middle of it."
            ))
        }

        if let target = geometry.headHeight.targetMM, let band = geometry.headHeight.passMM,
           target < band.min || target > band.max {
            found.append(SpecAdvisory(
                field: "geometry.headHeight.targetMM",
                message: "target \(Self.trim(target)) mm sits outside its own pass band \(Self.trim(band.min))-\(Self.trim(band.max)) mm."
            ))
        }

        return found
    }

    private static func trim(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%g", value)
    }
}
