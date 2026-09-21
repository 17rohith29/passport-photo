import Foundation
import Testing
import TestSupport
@testable import SpecKit

@Suite("Spec advisories")
struct SpecAdvisoryTests {

    @Test("in-passport is flagged for the dpi that disagrees with its pixel size")
    func indiaDPIAdvisory() throws {
        let spec = try SpecLoader.load(contentsOf: #require(RepoPaths.inPassportSpec))
        let advisory = try #require(spec.advisories.first { $0.field == "photo.digital.dpi" })

        #expect(advisory.message.contains("300"))
        #expect(advisory.message.contains("457"))
        #expect(advisory.message.contains("18 px/mm"))
    }

    @Test("an advisory does not stop the spec loading")
    func advisoriesAreNotFatal() throws {
        let spec = try SpecLoader.load(contentsOf: #require(RepoPaths.inPassportSpec))
        #expect(!spec.advisories.isEmpty)
        #expect(throws: Never.self) { try spec.validate() }
    }

    @Test("a dpi that agrees with the pixel size raises nothing")
    func consistentDPIIsQuiet() throws {
        // 413x531 px at 35x45 mm really is 300 dpi.
        let json = SpecValidationTests.validJSON(
            digital: #"{ "sizePx": { "width": 413, "height": 531 }, "format": "jpeg", "dpi": 300 }"#,
            headHeight: #"{ "measure": "chinToCrown", "targetMM": 30, "passMM": { "min": 25, "max": 35 } }"#
        )
        var object = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        var photo = try #require(object["photo"] as? [String: Any])
        photo["sizeMM"] = ["width": 35, "height": 45]
        object["photo"] = photo
        let spec = try SpecLoader.load(data: try JSONSerialization.data(withJSONObject: object))

        #expect(spec.advisories.isEmpty)
    }

    @Test("the square fixture is flagged for having no head-height target")
    func squareSpecHasNoTarget() throws {
        let spec = try SpecLoader.load(contentsOf: #require(RepoPaths.squareTestSpec))
        #expect(spec.advisories.contains { $0.field == "geometry.headHeight.targetMM" })
        // It states no dpi for the digital file, so that advisory must not fire.
        #expect(!spec.advisories.contains { $0.field == "photo.digital.dpi" })
    }

    @Test("a target outside its own pass band is flagged")
    func targetOutsideBand() throws {
        let json = SpecValidationTests.validJSON(
            headHeight: #"{ "measure": "chinToCrown", "targetMM": 40, "passMM": { "min": 25, "max": 35 } }"#
        )
        let spec = try SpecLoader.load(data: json)
        let advisory = try #require(spec.advisories.first { $0.field == "geometry.headHeight.targetMM" })
        #expect(advisory.message.contains("outside"))
    }

    @Test("in-passport's 36 mm target sits inside its own pass band")
    func indiaTargetIsInsideItsBand() throws {
        let spec = try SpecLoader.load(contentsOf: #require(RepoPaths.inPassportSpec))
        #expect(!spec.advisories.contains {
            $0.field == "geometry.headHeight.targetMM" && $0.message.contains("outside")
        })
    }
}
