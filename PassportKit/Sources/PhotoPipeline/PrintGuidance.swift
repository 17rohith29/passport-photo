import CoreGraphics
import Foundation
import SpecKit

/// What to do with the photo once it is saved.
///
/// Every word of this comes from the spec, so a new country gets correct advice without any
/// Swift being written: where to submit is `document.channel`, how many to cut is
/// `print.copiesRequired`, the paper is `print.paperFinish`, and the things the app could not
/// check are `status.notEnforced`.
public enum PrintGuidance {

    public enum Variant: String, Sendable, CaseIterable {
        /// The single image, for an online upload or for a shop to print.
        case single
        /// The multi-up sheet, for printing at home or at a photo counter.
        case sheet
    }

    public struct Step: Sendable, Identifiable, Equatable {
        public var symbol: String
        public var title: String
        public var detail: String
        public var id: String { title }
    }

    /// Standard consumer photo paper. Anything a shop prints "4 by 6" onto.
    public static let paperInches = CGSize(width: 4, height: 6)

    public static func steps(for spec: DocumentSpec, variant: Variant) -> [Step] {
        var steps: [Step] = []
        let size = "\(trim(spec.photo.sizeMM.width)) × \(trim(spec.photo.sizeMM.height)) mm"
        let copies = spec.photo.print.copiesRequired ?? 1

        switch variant {
        case .single:
            steps.append(Step(
                symbol: "arrow.up.doc",
                title: "Uploading it",
                detail: "Use the saved file as it is. Don't crop it, rotate it or run it through "
                    + "another app — it is already exactly \(outputSize(spec)) and \(size)."
            ))
            steps.append(Step(
                symbol: "printer",
                title: "Printing it instead",
                detail: "Ask for a \(trim(spec.photo.sizeMM.width)) × \(trim(spec.photo.sizeMM.height)) mm "
                    + "print, or go back and save the print sheet instead — it lays several out "
                    + "on one 4 × 6 inch sheet with cut guides."
            ))

        case .sheet:
            let perSheet = photosPerSheet(spec: spec)
            steps.append(Step(
                symbol: "printer",
                title: "Order a plain 4 × 6 inch print",
                detail: "Any photo counter or home printer will do. Do NOT ask for their passport "
                    + "photo service — you have already done that part."
            ))
            steps.append(Step(
                symbol: "slider.horizontal.3",
                title: "Turn off crop, zoom and enhance",
                detail: "Print at 100%, actual size, with no auto-correction. Scaling by even a "
                    + "few percent puts the head outside the \(headBandText(spec)) it has to be."
            ))
            steps.append(Step(
                symbol: "ruler",
                title: "Measure before you cut",
                detail: "The sheet holds \(perSheet) photos with grey cut guides. Measure one with "
                    + "a ruler first: it must be \(size). If it isn't, the print was scaled — "
                    + "print it again."
            ))
            steps.append(Step(
                symbol: "scissors",
                title: copies == 1 ? "Cut one photo out" : "Cut \(copies) photos out",
                detail: copies == 1
                    ? "This document needs one photo."
                    : "This document needs \(copies) identical photos."
            ))
        }

        if let finish = spec.photo.print.paperFinish, finish != .any, variant == .sheet {
            steps.append(Step(
                symbol: "doc.richtext",
                title: "Paper matters here",
                detail: "\(spec.country.name) asks for \(finish.rawValue) photo paper."
            ))
        }

        if let channel = spec.document.channel {
            steps.append(Step(
                symbol: "building.columns",
                title: "Where it goes",
                detail: "Submit to \(channel)."
            ))
        }

        return steps
    }

    /// The things the user still has to get right, which the app could not check.
    public static func remainingResponsibilities(for spec: DocumentSpec) -> [String] {
        spec.status.notEnforced ?? []
    }

    public static func photosPerSheet(spec: DocumentSpec) -> Int {
        let tile = SpecGeometry.printTilePx(spec: spec)
        let dpi = spec.photo.print.dpi
        let grid = PrintSheetComposer.layout(
            tileWidth: Int(tile.width), tileHeight: Int(tile.height),
            sheetWidth: Int((paperInches.width * dpi).rounded()),
            sheetHeight: Int((paperInches.height * dpi).rounded()),
            gutterPx: 40
        )
        return max(1, grid.columns * grid.rows)
    }

    static func outputSize(_ spec: DocumentSpec) -> String {
        guard let px = spec.photo.digital.outputSizePx else { return "the right size" }
        return "\(trim(px.width)) × \(trim(px.height)) pixels"
    }

    /// Rounded outwards to whole millimetres: a band printed as "35.25-36.75 mm" invites a
    /// precision no ruler has, and rounding inwards would state a tighter rule than the country's.
    static func headBandText(_ spec: DocumentSpec) -> String {
        guard let band = HeadHeightBand.inMM(spec: spec) else { return "the required size" }
        return "\(Int(band.min.rounded(.down)))–\(Int(band.max.rounded(.up))) mm"
    }

    static func trim(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%g", value)
    }
}
