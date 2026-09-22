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

## M5 follow-up — the flow actually runs (2026-09-21)

Prompted by "I pass in a photo and it's just spinning, 'Reading your photo' is not checked".

**Three real bugs, all found by running the app rather than the tests**
1. **The step list never ticked.** The whole pipeline ran under one hardcoded step, so the UI sat
   on step 2 forever and no step ever showed as done. `PassportPipeline.run` now reports a
   `PipelineStage` at each stage, `PhotoSession` tracks a `completed` set, and the view shows
   done / in-progress / waiting per step.
2. **The matte ran at full resolution.** `MatteRefiner` allocates several image-sized buffers
   (connected components, a signed distance field, a blur); at 24 MP that is hundreds of
   megabytes, fine on a Mac and not on a phone. Segmentation and refinement now run at
   `Tuning.matteWorkingSize` (2048 px) — the reference pipeline downsamples for the same reason —
   and the renderer samples the smaller matte rather than upscaling it into another full buffer.
   End to end went **2.875 s to 1.678 s** with the same result. Decode is also capped at 4500 px.
3. **A stage that threw left a dead end.** The rejection screen only rendered failed *checks*, so
   a thrown error produced a bare "This photo can't be used." with no reason at all. See
   LESSONS 17.

**The Simulator cannot run this app** (LESSONS 16). iOS 26.5 throws Vision code 9, "Could not
create inference context", on the first landmarks request. iOS 18.4 runs Vision but returns zero
faces for a photo macOS handles — indistinguishable from a real "no face". Both now surface as a
device limitation, with a different headline, no "choose another photo" button and no tips,
because nothing the user does in the Simulator will help.

**What was verified**
- 60 tests green in release, 6.6 s.
- `PhotoSessionTests` drive the exact flow the app runs: every stage completes, a good photo
  finishes with a renderable result and a print sheet, a rejected photo carries advice on every
  failure, garbage data fails cleanly instead of hanging, and reset clears state.
- `DecodeCapTests` pin that the new 4500 px decode cap still finds a face and agrees with the
  uncapped image on head height within 5% — the cap was the first suspect for the iOS 18 "no
  face" and was ruled out on macOS.
- Screens seen for real in the Simulator: Home, Processing, and the rejection screen in both its
  photo-problem and device-limitation forms.

**Open issues**
- **The Result screen has never been rendered.** No Simulator can reach it, and running the app on
  this Mac via "Designed for iPad" needs the Mac registered for development signing, which
  CLAUDE.md says to ask about first. It is the one screen still unverified by eye; its data is
  covered by `PhotoSessionTests`.
- Saving to Photos and Files is likewise unexercised — both need a real device.
- `MeasurementOverlay` now draws the measured crown and chin (`RenderedOutput.crownFraction` /
  `chinFraction`) rather than the spec's targets, but has not been seen on screen.

## Three countries, and hardening (2026-09-21)

**United States** — `specs/us-passport.json`, sourced from **8 FAM 402.1**, the State
Department's own adjudication manual (CT:CITZ-136, 12 Jan 2026), cross-checked against U.S.
Mission Poland's public page. 2 x 2 in (50.8 mm), head 25-35 mm, no glasses, 54 KB-10 MB.
Every source is `official`.

The FAM measures the facial image "from the top of the head (not the hairline or the applicant's
hair) to the bottom of the chin (not including facial hair)" — the **opposite** of this app,
which deliberately measures the hair mass and the beard (LESSONS 1 and 2). Ours therefore reads
larger than the official definition, so the target sits mid-band at 30 mm, leaving 5 mm either
way. Recorded in the spec's notes and pinned by a test.

**Schengen** — `specs/eu-schengen-visa.json`, sourced from the European Commission's own ICAO
photograph guidelines (DG Migration and Home Affairs). It differs from the others in three ways
that all exercised untested paths: the head is stated as a **percentage** (70-80%) rather than
millimetres, the background is **light grey**, not white, and **glasses are permitted**.

**The bug the third country found** — see LESSONS 18. A rule stated in a different unit was
silently dropped in three places, including `ComplianceChecker`, where the Schengen head height
was **never checked at all**. Fixed with `HeadHeightBand.inMM` and a public `eyeLineBand`, and
guarded by `SpecRenderabilityTests`, which walks every file in `specs/`.

**What was measured — IMG_0012 through all three specs**
| | India | United States | Schengen |
|---|---|---|---|
| output | 630x810 | 1200x1200 | 827x1063 |
| head | 35.39 mm (35.25-36.75) | 29.68 mm (25-35) | 33.44 mm (31.5-36.0) |
| background | white, 99.9% pure | white, 99.9% pure | grey #F0F0F0, 99.9% pure |
| verdict | meets requirements | meets requirements | meets requirements |
All three inspected by eye. All ten reject fixtures are rejected under all three specs.

**Bad input** — `BadInputTests` needs no private photos, so it runs on any clone: a blank wall,
pure noise, a 32 px image, 2000x10 and 10x2000 and 1x1, empty and corrupt bytes. The contract is
that the pipeline always returns, never crashes, and never emits a passport photo from something
that is not a usable portrait. `BadPortraitTests` builds harder cases from the owner's photos: a
two-person frame (rejected for faceCount) and a heavily blurred portrait (rejected for sharpness).

**UI** — the country picker became one card per spec, because a segmented control truncated
"Schengen Area, Schengen visa" at three entries. Cards come straight from the catalogue, so
adding a country still touches no Swift.

**Open issues**
- The Result screen is still unverified by eye; see the M5 follow-up entry.
- `earsVisible` is decoded and shown but no rule enforces it. India requires ears visible, the US
  and EU do not.
- Glasses are decoded and shown but not detected. Schengen permits them with conditions the app
  cannot check.
- The US spec's `topMargin` and eye band are this app's framing choices, not published figures.

## M6 — Polish (2026-09-21)

**The decode cap could reject a photo that would pass.** `docs/PLAN.md` asks for 48 MP inputs to
downsample "without dropping below required head pixels", and the 4500 px cap added earlier caps
the *frame*, not the head: on a 48 MP photo where the head fills a small part of the frame, the
cap scales a ~1100 px head to ~650 px, right on India's 648 px requirement. `PhotoSession` now
retries at full resolution when — and only when — the gate failed on `resolution` and the source
was actually larger than the cap. Nothing else is retried: every other rejection is about the
photo, not the decode.

**Dynamic Type.** At accessibility sizes the document card put a flag beside the text and
squeezed it into a column so narrow that "Passport" hyphenated to "Pass-port", and the large
navigation title truncated to "Passport Ph…". The card now stacks at accessibility sizes, the
title goes inline, long check text wraps instead of truncating, and the dimmed source photo on
the processing screen is dropped where vertical space is scarce. Verified at
`accessibility-extra-extra-extra-large`: nothing truncates.

**VoiceOver.** A check row read as a pile of fragments; it now reads as one sentence —
"Even lighting, failed. Measured 14.0% difference between cheeks. Needs under 12%. One side of
your face is brighter…". Progress steps announce done / in progress / waiting. The decorative
source photo and the flag are hidden from the reader.

**Haptics.** Three moments only: success, warning and failure on the verdict. Haptics that fire
on every navigation stop carrying information.

**Dark mode.** Verified in both appearances at normal and accessibility sizes.

**Performance.** 1.678 s end to end for a 24 MP photo in release on this Mac, inside the plan's
3 s target. **Still not measured on a real iPhone.**

**Dead code removed.** `ImageLoader.applying(_:to:)` — the hand-rolled EXIF orientation matrices
that produced the upside-down bug — was unreferenced and is gone, so nobody reaches for it again.

**Open issues**
- Perf and the Result screen still need a real device.
- The visual design is tidy and native but has had no art direction: no custom palette, no icon.

## M7 — Guided capture (2026-09-21)

Brought forward from "Later" at the owner's request: a mode that helps take the photo rather than
only judging one that already exists.

**The advice is pure code.** `CaptureGuidance` lives in `PhotoPipeline` and takes
`FaceMeasurements` plus a frame size and a spec, returning ordered cues. It reads the **same
spec and the same `GateCalibration`** as the import gate, so the camera asks for exactly what the
gate will accept. No camera, no Vision, no UI in it — 13 tests drive it without hardware.

**Distance is derived, not guessed.** The passport crop is `head / headFraction` tall, so aiming
the crop at ~75% of the frame puts the head at `0.75 × headFraction`: 0.60 of frame height for
India, 0.44 for the US, 0.56 for Schengen. The on-screen oval is that number, so filling it means
the head is the right size *for the selected document*. A test asserts the US band sits entirely
below India's.

**Cue order matters.** Framing first (nobody is helped by "lift your chin" while they are across
the room), then centring and camera height, then pose, then eyes and mouth. Lighting **advises
but never blocks**: a preview frame is too small and noisy to refuse someone on, and it is
measured properly on the full-resolution capture.

**Auto-capture needs a streak.** `CaptureStabiliser` requires six consecutive ready frames, so one
lucky frame cannot fire the shutter; a single bad frame resets it. The shutter ring fills as the
streak builds.

**Friend or tripod**, as asked: the tips list now leads with it, and choosing the front camera
shows "The back camera is sharper. Ask someone to hold the phone, or prop it up."

**App layer.** `CameraController` owns AVFoundation only: frames are analysed five times a second
rather than every frame, and spoken cues (`AVSpeechSynthesizer`) do not repeat until the cue
changes or three seconds pass. Frames are converted to `CGImage` **synchronously on the capture
queue**, because the `CVPixelBuffer` is recycled the moment the delegate returns — Swift 6 strict
concurrency caught the original version sending the buffer across actors.

**What was verified**
- 103 tests green in release; 13 of them are the capture coach, none need a camera.
- The capture screen renders and handles "no camera" cleanly in the Simulator, which is the only
  state the Simulator can show.

**Open issues**
- **The camera path has never run against a real camera.** The head-fraction bands, preview
  framing and the feel of the spoken cues all need a device to confirm.
- ~~Front-camera cues reversed.~~ Fixed: the preview mirrors the front camera, so the instruction
  is reversed while the measurement is not. Frames Vision measures and the captured photo are now
  explicitly never mirrored, and both connections are pinned to portrait.
- ~~The captured photo could vanish.~~ Fixed: two `fullScreenCover`s were fighting, so the photo
  is now held until the camera sheet has gone and processed in `onDismiss`.
- Burst best-frame selection from the plan is not implemented; auto-capture takes one photo.
- Lighting is not measured live at all (the cue only fires if a caller supplies a value).
