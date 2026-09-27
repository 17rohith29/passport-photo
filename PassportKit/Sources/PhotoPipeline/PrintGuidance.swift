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

    public static func steps(
        for spec: DocumentSpec, variant: Variant, mode: BackgroundMode = .replace
    ) -> [Step] {
        var steps: [Step] = []
        let size = sizeText(spec)
        let copies = spec.photo.print.copiesRequired ?? 1

        switch variant {
        case .single:
            steps.append(Step(
                symbol: "arrow.up.doc",
                title: "Upload it as it is",
                detail: "Use the saved file as it is. Don't crop it, rotate it or run it through "
                    + "another app. It is already exactly \(outputSize(spec)) and \(size)."
            ))
            steps.append(Step(
                symbol: "printer",
                title: "Print it instead",
                detail: "Ask for a \(size) print. If you would rather print several at once, "
                    + "save the print sheet as well when this screen offers it."
            ))

        case .sheet:
            let perSheet = photosPerSheet(spec: spec)
            steps.append(Step(
                symbol: "printer",
                title: "Order a plain 4 × 6 inch print",
                detail: "Use a photo counter or a lab print on photo paper. Several authorities "
                    + "reject home-printer output. Do NOT ask for their passport photo service; "
                    + "you have already done that part."
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
                    + "a ruler first: it must be \(size). If it is not, the print was scaled, so "
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
            // Never say "submit this" without the caveat when the authority would reject it on
            // sight for having been edited.
            // Only when we actually replaced it. On the kept path this pointed at a warning
            // the Saved screen deliberately does not show, about an edit that never happened.
            let edited = mode == .replace && spec.background?.editingRisk != nil
            steps.append(Step(
                symbol: "building.columns",
                title: "Where it goes",
                detail: edited
                    ? "Submit to \(channel). Read the warning above first: this photo has an edited background, which they may reject."
                    : "Submit to \(channel)."
            ))
        }

        return steps
    }

    /// The things the user still has to get right, which the app could not check.
    ///
    /// `notEnforced` is written for the usual path, where the background is replaced. When it
    /// was kept, those sentences are simply untrue, and one of them told the user the opposite
    /// of what the app had just done.
    public static func remainingResponsibilities(
        for spec: DocumentSpec, mode: BackgroundMode = .replace
    ) -> [String] {
        let stated = spec.status.notEnforced ?? []
        guard mode == .keep else { return stated }
        var out = stated.filter { !$0.localizedCaseInsensitiveContains("this app replaces") }
        if stated.count != out.count {
            out.append(
                "Your background was kept, so nothing was replaced. This photo was still "
                + "cropped, straightened and resized by software."
            )
        }
        return out
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

    /// The size as the user would say it at a counter. The US photo is universally "2 x 2 in";
    /// asking for a 50.8 mm print gets a blank look.
    public static func sizeText(_ spec: DocumentSpec) -> String {
        if let label = spec.photo.sizeLabel, !label.isEmpty { return label }
        return "\(trim(spec.photo.sizeMM.width)) × \(trim(spec.photo.sizeMM.height)) mm"
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
