# Progress

One entry per milestone: date, what changed, what was measured (include Vision's raw chin bias and yaw for IMG_0012), open issues.

## M0 — Scaffold (2026-09-21)

**What changed**
- `PassportKit` local package (`swift-tools-version: 6.0`, Swift 6 language mode, iOS 18 / macOS 15)
  with the three source targets — `SpecKit`, `PhotoAnalysis`, `PhotoPipeline` — wired in the
  dependency direction `PhotoPipeline -> PhotoAnalysis -> SpecKit`. `SpecKit` imports only Foundation.
- Three test targets: `SpecKitTests`, `PlannerTests`, `FixtureTests`.
- `TestSupport` target with `RepoPaths`: walks up from `#filePath` to the repo root so tests read
  `specs/` and `fixtures/` by path. `hasFixturePhotos` gates photo-dependent tests via
  `.enabled(if:)`, so a fresh clone without `fixtures/photos/` still goes green.
- `PassportPhoto.xcodeproj` (SwiftUI, iOS 18 deployment target, objectVersion 77 with a
  file-system-synchronized group, so new files in `PassportPhoto/` need no project edits).
  Shared scheme committed. The app links all three PassportKit libraries; `HomeView` is an
  M0 placeholder that imports `SpecKit`.
- `PhotoAnalysis` / `PhotoPipeline` are placeholders — the targets exist so the dependency
  direction is fixed from the start. Real types land at M2–M4.
- Filled in the Commands section of `CLAUDE.md`.

**What was measured**
- `swift test --package-path PassportKit`: 39 tests in 8 suites, all passing, ~0.01 s.
- `xcodebuild -scheme PassportPhoto` BUILD SUCCEEDED on both
  `platform=iOS Simulator,name=iPhone 17` (OS 26.5) and
  `platform=iOS Simulator,name=iPhone 16,OS=18.4` (the iOS 18 deployment floor).
- Toolchain: Xcode 26.5 (17F42), Swift 6.3.2, iOS SDK 26.5.

**Vision API availability (checked against the installed SDK, not assumed)**
The iOS 18 Swift Vision API is present and marked `@available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, *)`,
so the same code compiles for the app and for `swift test` on the Mac:
- `DetectFaceLandmarksRequest` -> `FaceObservation.landmarks` (`Landmarks2D`) — M2.
- `FaceObservation.roll` / `.yaw` / `.pitch`, each `Measurement<UnitAngle>` — M2, replaces the
  Python half-face yaw estimate per LESSONS 6.
- `DetectFaceCaptureQualityRequest` -> `faceCaptureQuality` — M2.
- `GeneratePersonSegmentationRequest` (has a `QualityLevel`, use `.accurate`) and
  `GenerateForegroundInstanceMaskRequest` -> `InstanceMaskObservation` — M3, compare on fixture edges.
- `DetectHumanBodyPoseRequest` available if the shoulders check needs it beyond the matte.

**Open issues**
- ~~`iPhone 16` has no iOS 26.5 runtime on this Mac.~~ Resolved: the primary command now targets
  `iPhone 17` (OS 26.5, owner's call). The pinned `iPhone 16,OS=18.4` command is kept as the
  iOS 18 deployment-floor check; both were verified to build.
- **Owed to this file: Vision's raw chin bias and yaw for IMG_0012.** Not yet measurable — it needs
  `VisionFaceAnalyzer`, so it is the first thing M2 must produce. LESSONS 1 predicts a landmark
  chin sitting 3.7–5% of head height high (dlib sat ~55 px high on this photo); LESSONS 6 wants
  Vision's yaw recorded against the Python estimate of 5.5° ± 2°. Do not close M2 without both
  numbers written here.

## M1 — Specs (2026-09-21)

**What changed**
- `DocumentSpec` and friends mirror `specs/document-spec.schema.json` one-to-one: `Codable`,
  `Sendable`, `Equatable`, value types throughout. Hyphenated enum cases (`id-card`,
  `residence-permit`, `official-partner`, `neutral-or-slight-smile`) carry explicit raw values.
- `SpecLoader.load(data:)` / `load(contentsOf:)` decode then validate. `DecodingError` is
  translated into a message that names the offending field and path
  (e.g. "missing required field 'country' at (root)") rather than dumping a coding-path struct.
- `DocumentSpec.validate()` enforces what Codable cannot and **collects every issue** so one load
  reports all of them: schemaVersion == 1, `id` and `country.code` patterns, `lastVerified` parses
  as yyyy-MM-dd, exactly one of `sizePx` / `sizePxRange`, `headHeight` has `passMM` or
  `passFraction`, no inverted ranges, `colorHex` is `#RRGGBB`, `sources` non-empty.
- `Units.mmToPx` / `pxToMM`, and `SpecGeometry` deriving `pxPerMM`, `requiredHeadPx` and
  `printTilePx` from the spec.
- `DocumentSpec.advisories` for non-fatal spec problems (see below).

**What was measured**
- `in-passport.json` and `specs/test/fixture-square.json` both decode and validate, with every
  field the pipeline depends on asserted (33 tests green).
- `requiredHeadPx` = **648.0 px**, matching the Python oracle's
  `need = px[1] * head_mm_target / size_mm[1]` = 810 * 36 / 45.
- `pxPerMM` = **18.0** (810 px / 45 mm). Print tiles = **413 x 531 px** at 300 dpi, matching
  `SPEC['print_px']` in `auto_passport.py`.
- IMG_0012's ground-truth head (1800 px) is 2.78x the requirement — consistent with the manifest's
  `head_px_ratio_vs_required: 2.82` (the small gap is the landmark-vs-ground-truth chin, not a bug).
- `fixtures/expected.json` decodes: 14 cases — 1 accept, 10 reject, 3 borderline. Every reason
  named in the manifest is in `checkIdVocabulary`, and every reject case names a primary reason.

**Decision worth keeping**
`SpecGeometry.pxPerMM` is derived from **the digital pixel size over the physical size**, not from
`photo.digital.dpi`. For in-passport those disagree: 630x810 at 35x45 mm is ~457 dpi, while
`dpi: 300` correctly describes only the print tiles (413x531). Using `dpi` here would have
computed head heights ~34% small and failed every head-size check for a reason that looks like a
geometry bug. Pinned by `pxPerMMIgnoresDPI` and `requiredHeadPxMatchesOracle`.

**How the dpi contradiction was resolved** (owner: "do what's right")
`digital.dpi` is not wrong, it is mislabelled. The Python reference writes it into the exported
file as metadata (`Image.save(..., dpi=(300,300))`) and never uses it for geometry — so deleting it
would lose a real field. Instead:
- The schema's `digital.dpi` description now states it is export metadata, that geometry comes from
  `sizePx / sizeMM`, and that the two can legitimately disagree. **No spec values were changed.**
- Added `DocumentSpec.advisories`: non-fatal problems, separate from `validate()`, which still
  throws only on specs that cannot be used. `in-passport` now reports, out loud, that it states
  300 dpi while 630x810 px at 35x45 mm implies 457 dpi, and that geometry uses 18 px/mm.
- Two more advisories earn their place: a `headHeight` with no `targetMM` (the planner would aim at
  a band limit instead of its middle — this fires on the square fixture), and a `targetMM` outside
  its own `passMM` band.
Advisories are for whoever edits `specs/`, never shown to users.

**Open issues**
- `PlannerTests` and `FixtureTests` currently assert scaffolding and the manifest only. The real
  geometry and per-photo assertions arrive at M3/M2 respectively.
- Nothing surfaces advisories yet. When the requirements sheet is built at M5, decide whether a
  low-confidence spec should show anything to the user (the spec already carries `status.confidence`
  and `notes` for that purpose; advisories are a separate, developer-facing channel).

## M2-M4 — Analysis, geometry, render and verify (2026-09-21)

**What changed**
- PhotoAnalysis: `ImageLoader`, `VisionFaceAnalyzer`, `ImageMetrics`, `ChinRefiner`,
  `VisionSubjectSegmenter`, `MatteRefiner`, `CrownFinder`, `Tuning`.
- PhotoPipeline: `InputGate` + `GateCalibration`, `CropPlanner`, `Leveler`, `Renderer`,
  `PrintSheetComposer`, `JPEGExporter`, `ComplianceChecker`, `PassportPipeline`.

**What was measured — IMG_0012, against `fixtures/expected.json`**
| | measured | required |
|---|---|---|
| crown y | 948 px | 936 ± 15 |
| chin y | 2742 px | 2736 ± 15 |
| head | 1794 px | 1800 ± 25 |
| head | 35.39 mm | 35.25–36.75 |
| top margin | 2.83 mm | 1.5–4.0 |
| eye line | 54.7% | 50–60% |
| roll | 0.19° | under 2° |
| background | 99.9% pure, darkest 245 | ≥95%, ≥245 |
| faceIntegrity | 0.00% | under 0.5% |
| file | 134 KB | 10–250 |

Verdict `meetsRequirements` with **no warnings**. Output inspected by eye against
`fixtures/reference_output/` and matches it; mine keeps slightly less flyaway hair.
All 14 fixtures behave as the manifest states. 52 tests green.

**Vision's raw numbers for IMG_0012** (owed since M0)
- **Chin bias: the landmark chin sits 40.9 px above the true chin, 2.27% of head height.**
  dlib's was ~55 px. Same direction as LESSONS 1, smaller magnitude.
- **Yaw 3.78°** (Python estimated 5.5° ± 2°, and its own report FAILed the photo at 5.5°).
  Under the spec's 5° warn threshold, so the golden case now passes yaw outright.
- Pitch -1.54°, capture quality 0.625.

**Four bugs only real photos could have found** — see the M2-M4 commit message for detail:
EXIF orientation flipped every 24 MP HEIC upside down; the Leveler rotated the wrong way and
doubled the tilt; Vision's pose roll is not the eye-line angle; and the cheek metric had to be
rebuilt twice before it ranked IMG_0012 below IMG_0010.

**Performance**
2.875 s end to end for a 24 MP photo in release on this Mac — inside the M6 target. Debug is
141 s, because PassportKit compiles unoptimised. Anyone testing the app on a device must switch
the Run configuration to Release or it looks like a hang.

**Open issues**
- The renderer is scalar Swift. It hits the target already, but Accelerate or Metal would give
  headroom for 48 MP inputs (M6).
- `GateCalibration.maxMouthOpenness` is 0.070, splitting IMG_0009 (0.083, a required rejection)
  from IMG_0016 (0.059). That is a 0.024 gap on one photo — it needs more faces before it can be
  trusted as a general threshold.
- Cheek imbalance now runs lower than the Python's on every fixture (0.036 vs 0.089 on IMG_0012),
  because it is a different, more robust estimator. The spec's 0.08/0.12 thresholds were taken
  from the Python's scale, so they are effectively stricter in ranking than in absolute value.
  The two decisions the manifest forces are pinned by tests, but the thresholds deserve a look
  once there are more faces.

## M5 — App flow (2026-09-21)

**What changed**
- `SpecCatalog` loads every bundled spec and hides `isTestFixture` ones. `specs/` is a
  synchronized folder in the Xcode project, so adding a country adds no code.
- Screens: `HomeView` (spec-driven document card, Choose Photo, Import from Files, tips),
  `RequirementsSheet` (every number read from the spec, with sources, `lastVerified`, confidence,
  and an explicit "can't guarantee acceptance" line), `ProcessingView` (real step list, no fake
  progress bar), `RejectionView` (headline naming the main problem, then measured vs required vs
  how to fix), `ResultView` (verdict pill, all-checks sheet, measurements toggle, Upload/Print
  segmented control, Save menu), plus the printing instructions after saving.
- `PhotoSessionModel` drives the pipeline off the main actor, supports cancel, and saves to
  Photos with **add-only** authorization or to Files via `fileExporter`.
- `INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription` added — without it, saving crashes.

**What was measured**
Builds and runs on the iPhone 17 simulator; the Home screen renders the India card from
`in-passport.json`. The end-to-end flow inside the app has **not** been driven yet — simulator
control was not granted — so the UI beyond Home is unverified by me.

**Open issues**
- Drive the whole flow on a real device with a real photo. That is the next thing to do.
- `MeasurementOverlay` derives its crown/chin lines from the spec's target top margin rather than
  from where the head actually landed, so the lines are nominal, not measured. Fix before M6.
- No Dynamic Type / VoiceOver / dark mode pass yet (M6).
