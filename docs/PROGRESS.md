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
