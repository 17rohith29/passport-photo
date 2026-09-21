# Architecture

## Layout

```
PassportPhoto/                      Xcode project (SwiftUI app target)
  App/                              screens, view models, navigation
PassportKit/                        local Swift package, platforms: iOS 18, macOS 15
  Sources/
    SpecKit/                        DocumentSpec models, JSON loading, validation, unit conversion
    PhotoAnalysis/                  Vision-backed face analysis and segmentation, plus pure measurement code
    PhotoPipeline/                  gates, crop planning, rendering, print sheets, compliance, orchestration
  Tests/
    SpecKitTests/                   decoding, schema rules, unit conversion
    PlannerTests/                   pure geometry, no images
    FixtureTests/                   real photos from fixtures/, asserts fixtures/expected.json
specs/                              one JSON file per document, plus the schema
fixtures/                           test photos (gitignored), expected.json, reference output
reference/python/                   working reference pipeline (behavioral oracle)
```

Dependency direction: `App -> PhotoPipeline -> PhotoAnalysis -> SpecKit`. `SpecKit` imports only Foundation. Nothing in `PassportKit` imports SwiftUI or UIKit.

## Pipeline

```
import (PhotosPicker / fileImporter)
  -> decode + apply EXIF orientation            CGImage, top-left pixel space
  -> FaceAnalyzer.analyze                        FaceMeasurements (landmarks, pose, capture quality)
  -> InputGate (spec-driven rules)               [CheckResult]; any .fail stops here
  -> Leveler                                     rotate about the eye midpoint to zero roll
  -> FaceAnalyzer.analyze (again, on the levelled image)
  -> SubjectSegmenter.matte                      soft alpha, full resolution
  -> MatteRefiner                                hole fill, rim cleanup, variable-width edge band
  -> CrownFinder + ChinRefiner                   crown y, chin y (see LESSONS 1-2)
  -> CropPlanner (pure)                          CropPlan: rect in levelled pixels, output size
  -> Renderer                                    decontaminate, composite on spec background, one area-average downscale, subject-only sharpening
  -> PrintSheetComposer                          N-up sheet at exact 100% scale
  -> ComplianceChecker (re-detects on the output) [CheckResult]
  -> PipelineResult                              verdict, input checks, output checks, images, JPEG data
```

Each arrow is a protocol or a pure function, so any stage can be replaced or tested in isolation.

## Key types (sketch; refine while building)

```swift
// SpecKit
struct DocumentSpec: Codable, Sendable, Identifiable { ... }        // mirrors specs/document-spec.schema.json
struct Threshold: Codable, Sendable { var warnAbove: Double?; var failAbove: Double?; var warnBelow: Double?; var failBelow: Double? }
struct Range: Codable, Sendable { var min: Double; var max: Double }
struct SpecGeometry { /* derived: px per mm, required head px, target crop fractions */ }

// PhotoAnalysis
struct FaceMeasurements: Sendable {
    var faceCount: Int
    var leftEye, rightEye: CGPoint            // pixel centres
    var contour: [CGPoint]                    // jaw/face contour, pixels
    var rawChin: CGPoint                      // lowest contour point, before refinement
    var yawDeg, pitchDeg, rollDeg: Double     // from Vision's face observation
    var captureQuality: Double?               // Vision face capture quality
    var eyeOpenness: Double, mouthOpenness: Double
}
protocol FaceAnalyzing: Sendable { func analyze(_ image: CGImage) async throws -> FaceMeasurements }
protocol SubjectSegmenting: Sendable { func matte(for image: CGImage) async throws -> AlphaMatte }
enum ChinRefiner  { static func refine(image: CGImage, face: FaceMeasurements, tuning: Tuning) -> CGFloat }   // pure
enum CrownFinder  { static func find(matte: AlphaMatte, face: FaceMeasurements, tuning: Tuning) -> CGFloat }  // pure
enum ImageMetrics { static func sharpness(...) -> Double; static func cheekImbalance(...) -> Double }        // pure, Accelerate

// PhotoPipeline
enum CheckID: String, Codable { case faceCount, resolution, sharpness, lighting, yaw, pitch, roll, eyesOpen, mouthClosed,
                                    dimensions, fileSize, headHeight, topMargin, eyeLine, centering, background,
                                    faceIntegrity, shouldersVisible }
enum CheckStatus { case pass, warn, fail }
struct CheckResult: Sendable, Identifiable {
    var id: CheckID; var status: CheckStatus
    var measured: String; var requirement: String      // human-readable, units included
    var userMessage: String?                           // what to do about it
    var fixability: Fixability                         // .automatic or .retakeRequired
}
protocol ComplianceRule { var id: CheckID { get }; func applies(to spec: DocumentSpec) -> Bool; func evaluate(_ ctx: RuleContext) -> CheckResult }
struct CropPlan: Equatable { var rect: CGRect; var outputSize: CGSize; var scale: Double }
enum CropPlanner { static func plan(crown: CGFloat, chin: CGFloat, eyes: (CGPoint, CGPoint), imageSize: CGSize, spec: DocumentSpec) -> Result<CropPlan, PlanError> }
struct PipelineResult: Sendable { var verdict: Verdict; var inputChecks: [CheckResult]; var outputChecks: [CheckResult]; var output: RenderedOutput? }
actor PassportPipeline { init(analyzer: FaceAnalyzing, segmenter: SubjectSegmenting, tuning: Tuning = .default); func run(_ image: CGImage, spec: DocumentSpec) async -> PipelineResult }
```

**The rule engine is what makes countries reusable.** Each check is a `ComplianceRule`. A rule applies only when the spec contains its section. A new country with an extra constraint (say, "ears visible") means one new rule and one new optional schema field, with no changes to the pipeline.

## Python reference to Swift

| Python (`reference/python/`) | Swift component | Notes |
|---|---|---|
| `load()` (EXIF transpose) | `ImageLoader` | Apply `CGImagePropertyOrientation` before anything else |
| `chin.landmarks()` (dlib 68-point) | `VisionFaceAnalyzer` | Vision face landmarks (76-point constellation) plus face observation roll, yaw and pitch |
| `metrics_from_landmarks()` | `ImageMetrics` + `FaceMeasurements` | Yaw and pitch come from Vision directly. The Python yaw was a rough estimate (see LESSONS 6) |
| `ear()`, mouth ratio | eye/mouth openness from landmarks | Re-calibrate thresholds on fixtures |
| `chin.refine_chin()` | `ChinRefiner` | Port the algorithm: texture walk below the landmark chin, with an edge fallback for clean-shaven faces |
| `segment()` (isnet via rembg) | `VisionSubjectSegmenter` | Try person segmentation at `.accurate` and the foreground instance mask; pick by fixture edge quality |
| `matte()` (closed-form matting, variable band, rim cleanup, hole fill) | `MatteRefiner` | Closed-form matting is too slow on device. Keep hole fill, rim-only cleanup and the variable band idea; use a guided filter (Metal or Accelerate) if edges need refining |
| `find_crown()` | `CrownFinder` | First row where the mask spans at least 8% of face width |
| crop maths in `main()` | `CropPlanner` | Pure, unit-tested. Top-gap target first, then keep the eye line inside its band |
| `render()` (estimate_foreground_ml, composite, INTER_AREA, two-stage unsharp, edge revert) | `Renderer` | Core Image. Decontaminate edge colour or grey halos appear in hair |
| print sheet in `main()` | `PrintSheetComposer` | Grid computed from spec photo size and paper size, never hard-coded 2x3 |
| `validate()` | `ComplianceChecker` | Must re-detect on the output image, not reuse planning values (LESSONS 13) |
| `SPEC` dict | `specs/in-passport.json` | Every number moves to JSON |
| magic numbers (1.64, 1.2, 0.08, 0.35, sharpen params) | `Tuning` | One struct, each value commented with its origin and pinning fixture |

## Coordinate systems (a classic bug source)

- **Vision:** normalized coordinates, origin **bottom-left**, relative to the image passed in, after the orientation you give it.
- **Core Image:** pixel coordinates, origin **bottom-left**.
- **PassportKit internal:** pixel coordinates, origin **top-left**, y down, on the oriented image.

Convert only inside `VisionFaceAnalyzer`, `VisionSubjectSegmenter` and `Renderer`. `PlannerTests` should include a round-trip test for each conversion.

## Adding a country or document

1. Copy `specs/in-passport.json`, fill in the values, and list the sources with a `lastVerified` date.
2. If it needs a constraint the schema can't express, add an optional schema field and one `ComplianceRule`.
3. Add fixtures and expectations if you have photos, or at minimum `PlannerTests` cases for the new geometry.
4. `specs/test/fixture-square.json` is a deliberately fake square spec. Keep tests passing against it so no code quietly assumes 35x45 or 7:9.

## Testing

- `PlannerTests`: pure geometry, fast, no images. Include the square fake spec.
- `FixtureTests` (macOS, `swift test`): every case in `fixtures/expected.json`. Assert verdicts and primary reasons exactly, and numbers only within the stated tolerances. Write debug PNGs to `/tmp/passportkit-debug/`.
- Device smoke test: run IMG_0012 on a real iPhone and compare it with `fixtures/reference_output/`. Record timing.
