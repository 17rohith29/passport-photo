import Foundation
import SpecKit
import Testing
import TestSupport
@testable import PhotoPipeline

/// App Review rejected the first submission under guideline 1.1.6, misleading content, and the
/// reason was visible on the app's own result screen. The headline read "Meets requirements"
/// above an orange banner saying the photo broke a rule the authority enforces, because the
/// editing risk was drawn as a banner and never reached `Verdict.from`. The banner was the
/// disclaimer; the headline was the claim that contradicted it.
///
/// Two things have to stay true now. The verdict speaks only for what was measured, and a
/// replaced background counts against the verdict rather than sitting beside it.
@Suite("Verdict language")
struct VerdictLanguageTests {

    static func specs() throws -> [DocumentSpec] {
        let dir = try #require(RepoPaths.specs)
        return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.contains("schema") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { try JSONDecoder().decode(DocumentSpec.self, from: Data(contentsOf: $0)) }
    }

    @Test("no verdict claims the requirements are met")
    func headlinesClaimOnlyMeasurement() {
        let banned = ["meets requirement", "meets the requirement", "compliant", "approved",
                      "accepted", "guaranteed", "will pass", "valid"]
        for verdict in [Verdict.inRange, .inRangeWithWarnings, .cannotUse] {
            let headline = verdict.headline.lowercased()
            for phrase in banned {
                #expect(
                    !headline.contains(phrase),
                    "verdict headline \"\(verdict.headline)\" claims acceptance via \"\(phrase)\""
                )
            }
        }
    }

    @Test("a warning downgrades the verdict out of the clean state")
    func warningsDowngrade() {
        let pass = CheckResult(id: .dimensions, status: .pass,
                               measured: "600x600", requirement: "600x600")
        let warn = CheckResult(id: .unedited, status: .warn,
                               measured: "background replaced", requirement: "unedited")
        let fail = CheckResult(id: .headHeight, status: .fail,
                               measured: "12 mm", requirement: "25-35 mm")

        #expect(Verdict.from([pass]) == .inRange)
        #expect(Verdict.from([pass, warn]) == .inRangeWithWarnings)
        #expect(Verdict.from([pass, warn, fail]) == .cannotUse)
    }

    /// The check only fires when the document says something about editing, so a document that
    /// forbids it while publishing no risk text would slip through silently.
    @Test("every document that forbids editing also carries the text that triggers the check")
    func forbiddenDocumentsCarryRiskText() throws {
        for spec in try Self.specs() where spec.forbidsEditing {
            #expect(
                spec.background?.editingRisk != nil,
                "\(spec.id) forbids editing but has no editingRisk, so a replaced background would earn a clean verdict"
            )
        }
    }
}
