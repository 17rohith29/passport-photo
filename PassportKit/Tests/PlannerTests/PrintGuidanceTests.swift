import Foundation
import SpecKit
import Testing
@testable import PhotoPipeline

/// The advice shown after saving is generated from the spec, so a new country gets correct
/// printing steps without any Swift being written. These tests hold that line.
@Suite struct PrintGuidanceTests {

    static func specs() throws -> [DocumentSpec] {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("specs")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.contains("schema") }
        return try files.map { try SpecLoader.load(contentsOf: $0) }
            .filter { $0.status.isTestFixture != true }
            .sorted { $0.id < $1.id }
    }

    @Test func everyDocumentProducesUsableSteps() throws {
        for spec in try Self.specs() {
            for variant in PrintGuidance.Variant.allCases {
                let steps = PrintGuidance.steps(for: spec, variant: variant)
                #expect(steps.count >= 2, "\(spec.id) \(variant) had \(steps.count) steps")
                for step in steps {
                    #expect(!step.title.isEmpty)
                    #expect(!step.detail.isEmpty)
                    #expect(!step.symbol.isEmpty)
                    // A placeholder leaking into user-facing copy is the failure mode here.
                    #expect(!step.detail.contains("nil"), "\(spec.id): \(step.detail)")
                    #expect(!step.detail.contains("Optional"), "\(spec.id): \(step.detail)")
                }
            }
        }
    }

    @Test func sheetStepsSayHowManyCopiesTheCountryNeeds() throws {
        for spec in try Self.specs() {
            let copies = spec.photo.print.copiesRequired ?? 1
            let steps = PrintGuidance.steps(for: spec, variant: .sheet)
            let cutStep = try #require(steps.first { $0.symbol == "scissors" }, "\(spec.id)")
            #expect(
                cutStep.title.contains(copies == 1 ? "one" : String(copies)),
                "\(spec.id) needs \(copies) copies but said: \(cutStep.title)"
            )
        }
    }

    @Test func sheetStepsQuoteTheRealCutSize() throws {
        for spec in try Self.specs() {
            let steps = PrintGuidance.steps(for: spec, variant: .sheet)
            let measure = try #require(steps.first { $0.symbol == "ruler" }, "\(spec.id)")
            let size = PrintGuidance.sizeText(spec)
            #expect(measure.detail.contains(size), "\(spec.id) missing \(size): \(measure.detail)")
        }
    }

    @Test func photosPerSheetMatchesTheSheetThatIsActuallyComposed() throws {
        // If these ever disagree the user is told to cut a number of photos that is not there.
        for spec in try Self.specs() {
            let tile = SpecGeometry.printTilePx(spec: spec)
            let grid = PrintSheetComposer.layout(
                tileWidth: Int(tile.width), tileHeight: Int(tile.height),
                sheetWidth: Int((PrintGuidance.paperInches.width * spec.photo.print.dpi).rounded()),
                sheetHeight: Int((PrintGuidance.paperInches.height * spec.photo.print.dpi).rounded()),
                gutterPx: 40
            )
            #expect(PrintGuidance.photosPerSheet(spec: spec) == grid.columns * grid.rows, "\(spec.id)")
        }
    }

    @Test func aSheetHoldsAtLeastAsManyPhotosAsTheDocumentDemands() throws {
        for spec in try Self.specs() {
            let needed = spec.photo.print.copiesRequired ?? 1
            let available = PrintGuidance.photosPerSheet(spec: spec)
            #expect(
                available >= needed,
                "\(spec.id): one 4x6 sheet holds \(available) but \(needed) are required"
            )
        }
    }

    @Test func glossyOnlyCountriesSaySo() throws {
        let specs = try Self.specs()
        for spec in specs where spec.photo.print.paperFinish == .glossy {
            let steps = PrintGuidance.steps(for: spec, variant: .sheet)
            #expect(
                steps.contains { $0.detail.localizedCaseInsensitiveContains("glossy") },
                "\(spec.id) requires glossy paper but the advice never mentions it"
            )
        }
        // Guard against the fixtures quietly losing the countries that make this test meaningful.
        #expect(specs.contains { $0.photo.print.paperFinish == .glossy })
    }

    @Test func submissionChannelIsNamedWhenTheSpecKnowsIt() throws {
        for spec in try Self.specs() {
            guard let channel = spec.document.channel else { continue }
            let steps = PrintGuidance.steps(for: spec, variant: .single)
            #expect(steps.contains { $0.detail.contains(channel) }, "\(spec.id)")
        }
    }

    @Test func remainingResponsibilitiesComeStraightFromTheSpec() throws {
        for spec in try Self.specs() {
            #expect(PrintGuidance.remainingResponsibilities(for: spec) == (spec.status.notEnforced ?? []))
            // Every shipping document should tell the user what it could not check.
            #expect(!PrintGuidance.remainingResponsibilities(for: spec).isEmpty, "\(spec.id)")
        }
    }

    @Test func singlePhotoAdviceWarnsAgainstReEditing() throws {
        for spec in try Self.specs() {
            let steps = PrintGuidance.steps(for: spec, variant: .single)
            #expect(steps.contains { $0.detail.localizedCaseInsensitiveContains("don't crop") }, "\(spec.id)")
        }
    }

    /// `sizeLabel` is what the user says at a counter, so it must describe the same physical
    /// photo as `sizeMM`. A label that disagrees would send someone home with the wrong print.
    @Test func sizeLabelsDescribeTheRealSize() throws {
        for spec in try Self.specs() {
            guard let label = spec.photo.sizeLabel else { continue }
            #expect(!label.isEmpty, "\(spec.id)")
            let numbers = label.split(whereSeparator: { !"0123456789.".contains($0) })
                .compactMap { Double($0) }
            #expect(numbers.count >= 2, "\(spec.id): cannot read a size out of '\(label)'")

            let inInches = label.localizedCaseInsensitiveContains("in")
            let factor = inInches ? 25.4 : 1.0
            let widthMM = numbers[0] * factor, heightMM = numbers[1] * factor
            #expect(
                abs(widthMM - spec.photo.sizeMM.width) < 0.5,
                "\(spec.id): label says \(widthMM) mm wide, spec says \(spec.photo.sizeMM.width)"
            )
            #expect(
                abs(heightMM - spec.photo.sizeMM.height) < 0.5,
                "\(spec.id): label says \(heightMM) mm tall, spec says \(spec.photo.sizeMM.height)"
            )
        }
    }

    /// The US photo is universally "2 x 2 in" - on travel.state.gov, on the drugstore kiosk, and
    /// out of the mouth of the person at the counter. 50.8 mm is a conversion artefact.
    @Test func americanAdviceIsInInches() throws {
        let us = try #require(Self.specs().first { $0.id == "us-passport" })
        for variant in PrintGuidance.Variant.allCases {
            let text = PrintGuidance.steps(for: us, variant: variant).map(\.detail).joined()
            #expect(text.contains("2 × 2 in"), "\(variant): \(text)")
            #expect(!text.contains("50.8"), "millimetres leaked into US advice: \(text)")
        }
    }

    @Test func degenerateTileNeverDividesByZero() {
        let grid = PrintSheetComposer.layout(
            tileWidth: 0, tileHeight: 0, sheetWidth: 1200, sheetHeight: 1800, gutterPx: 40
        )
        #expect(grid == (1, 1))
    }

    @Test func trimDropsTrailingZeroesButKeepsRealDecimals() {
        #expect(PrintGuidance.trim(35) == "35")
        #expect(PrintGuidance.trim(50.8) == "50.8")
    }
}
