# Plan

## v1 goal

A user imports one photo and gets back a 35x45 mm Indian passport photo (a 630x810 JPEG for upload, and a 4x6 in print sheet) that measurably meets the spec, or a clear explanation of why their photo can't be used and what to do instead. Everything runs on-device. Results save to Photos or Files.

Out of scope for v1: camera capture, voice guidance, other countries (the code must support them; the data isn't there yet), accounts, payments, sharing, AirPrint.

## Milestones

Each milestone ends with `swift test` green, the app building, and an entry in `docs/PROGRESS.md`.

**M0: Scaffold.** Xcode project (iOS 18, SwiftUI) plus the local `PassportKit` package (iOS 18 and macOS 15) with the three targets and three test targets from `ARCHITECTURE.md`. Fill in the Commands section of `CLAUDE.md`. Load fixtures from the repo path in tests; skip cleanly if `fixtures/photos` is absent.

**M1: Specs.** `DocumentSpec` decodes `specs/in-passport.json` and `specs/test/fixture-square.json`. Validation rejects malformed specs with readable errors. Unit conversion helpers (mm to px, required head px). Tests for all of it.

**M2: Analysis.** `VisionFaceAnalyzer`, `ImageMetrics` (sharpness, cheek imbalance), `ChinRefiner`. Input gate rules. Acceptance: every `fixtures/expected.json` case that expects a rejection is rejected for the listed primary reason, and IMG_0012 passes the gate (a yaw warning is allowed). Record Vision's raw chin bias on IMG_0012.

**M3: Segmentation and geometry.** `VisionSubjectSegmenter` (compare person segmentation `.accurate` with the foreground instance mask, and keep the better one on fixture edges), `MatteRefiner`, `CrownFinder`, `CropPlanner`. Acceptance: IMG_0012 crown, chin and head-height pixels within `expected.json` tolerances. `PlannerTests` cover the square fake spec, eye-line clamping and crops that hit the image edge.

**M4: Render and verify.** `Renderer`, `PrintSheetComposer`, JPEG export (meet the spec's KB range by lowering quality in steps and never resizing), `ComplianceChecker` re-detecting on the output. Acceptance: IMG_0012 output meets every numeric bound in `expected.json`, `faceIntegrity` passes, and the debug PNG looks indistinguishable from `fixtures/reference_output/in-passport_IMG_0012.jpg` when inspected.

**M5: App flow.** The screens below, wired to `PassportPipeline`. Save to Photos (add-only permission) and to Files (`fileExporter`, both images). Error and permission-denied states.

**M6: Polish.** Visual design pass, Dynamic Type, VoiceOver labels, dark mode, haptics, performance on a real iPhone (target under 3 s end to end for a 24 MP photo), memory under control for 48 MP ProRAW-sized inputs (downsample on decode if needed without dropping below required head pixels).

**Later:** M7 guided capture (rear camera, live checks from the same rules, spoken cues, auto-capture on all-green with burst best-frame). M8 more countries.

## UI spec

Native iOS, restrained, confident. SF Symbols, system materials, `NavigationStack`. The photo is the hero on every screen. No clutter, no gradients, no stock illustrations. One primary action per screen.

### 1. Home
- Title: "Passport Photo".
- A document card: flag, "India, Passport", "35 × 45 mm, white background". Tapping it shows the requirements sheet. Other countries appear later as more cards; for now a quiet "More countries coming" row.
- Primary button: **Choose Photo**. Secondary: "Import from Files".
- A short "Tips for a photo that works" disclosure: face a window, plain light wall behind you, phone at eye level about 1.5 m away, rear camera with the 2x lens, neutral expression, no glasses.

### 2. Requirements sheet (from the spec, not hard-coded)
- Key numbers in plain language: size, head height, background, expression, glasses.
- Sources with links, "Last verified 20 Sep 2026", and a one-line note on confidence ("Head size guidance varies between sources; we target 36 mm, which fits all of them").

### 3. Processing
- The imported photo, dimmed, with a live checklist that ticks through: Checking photo quality → Finding your face → Removing background → Cropping to 35 × 45 mm → Verifying.
- Cancel button. No fake progress bars.

### 4. Can't use this photo
- The photo, with the problem areas marked where it helps (for example, cheek patches for lighting).
- A headline naming the main problem ("Your face is lit unevenly"), then each failed check as a row: what we measured, what's required, and how to fix it ("Face a window or a lamp directly in front of you").
- Primary: **Choose Another Photo**. Secondary: tips.

### 5. Result
- The finished 35 × 45 photo, large, on a subtle neutral backdrop so its white background reads as a photo.
- A toggle for **Measurements**: overlays crown, chin and eye lines with a mm ruler, like the owner's comparison images.
- Verdict pill: "Meets requirements" (green) or "Meets requirements with warnings" (amber). Tapping it opens the full check list (pass/warn per check, measured vs required).
- A segmented control switches between **Upload file** (630 × 810) and **Print sheet** (4 × 6 in, six copies).
- A one-line note: "Background replaced. Upload to the Passport Seva portal first; it checks the photo instantly."
- Primary: **Save**. It opens a small menu: Save to Photos, Save to Files.

### 6. Saved
- Confirmation with the file names, plus printing instructions: order a standard 4 × 6 print (not the store's passport service), turn off crop, zoom and enhance, and measure one photo (35 × 45 mm) before cutting.

### Copy guidelines
Plain, direct and specific. Always give the measured number and the fix. Never "AI-powered", never "guaranteed". Read every message aloud once; if it sounds like a form error, rewrite it.

## Acceptance for v1 overall
- Every case in `fixtures/expected.json` behaves as stated.
- IMG_0012 output within all numeric bounds, `faceIntegrity` passing, and visually indistinguishable from the reference output.
- No country numbers anywhere in Swift (grep for 35, 45, 630, 810 in `Sources/` returns only tests and comments).
- The fake square spec renders a correct square photo in `PlannerTests` and one fixture test.
- Works in light and dark mode at the largest Dynamic Type size without truncating key text.
