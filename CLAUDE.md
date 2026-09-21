# PassportPhoto

iOS 18+ app that turns an imported photo into a compliant passport photo, fully on-device.

- **v1 scope:** import a photo, check it, process it, save the results to Photos or Files.
- **Later milestone:** guided capture with the rear camera and spoken positioning cues. Not in v1.
- **Countries:** India passport first. Every country and document is data (a JSON spec in `specs/`), never code. Adding a country should mean adding a JSON file plus, at most, a new rule type.

## Read before writing code

1. `docs/PLAN.md`: milestones, UI spec, acceptance criteria. This is the source of truth for scope.
2. `docs/ARCHITECTURE.md`: modules, protocols, coordinate systems, and how to add a country.
3. `docs/LESSONS.md`: failure modes found while prototyping. Each one is a test that must stay green.
4. `specs/in-passport.json` and `specs/document-spec.schema.json`: the requirements, with sources.
5. `fixtures/expected.json`: the test photos and what the app must do with each one.
6. `reference/python/`: a working reference pipeline. Treat it as a behavioral oracle, not code to transliterate. It uses dlib, rembg and pymatting; the app uses Apple frameworks.

## Non-negotiables

1. **Never alter facial features.** No generative or "AI enhance" models touch the face. Use ML only for perception (landmarks, pose, segmentation) and deterministic code for geometry and compositing. The only allowed pixel changes on the subject are resampling, colour decontamination at the edges, and mild unsharp masking.
2. **Never upscale the source.** If the head is too few pixels for the output size, reject the photo and tell the user to use a closer or sharper one.
3. **Reject what processing can't fix,** before processing: uneven lighting, head turn or tilt, blur, eyes closed, mouth open, too-low resolution, more or fewer than one face. Every rejection says why, with the measured value and how to fix it.
4. **No country numbers in Swift.** All country-specific values live in `specs/*.json`. Algorithm tuning constants live in one `Tuning` type, each with a comment saying where it came from and which fixture pins it.
5. **On-device only.** No network, analytics or uploads.
6. **Never claim guaranteed acceptance.** The UI says "meets the measured requirements" and exposes the spec's sources, last-verified date and confidence.
7. **`PassportKit` builds for macOS 15 as well as iOS 18,** so the fixture suite runs with `swift test` on the Mac. Several Vision requests are limited or behave differently in the iOS Simulator.

## Conventions

- Swift 6 with strict concurrency, SwiftUI, `@Observable`, async/await.
- Value types for results. Protocols for anything backed by Vision or Core Image, so tests can inject fakes.
- Apple frameworks only in v1: Vision, Core Image, Accelerate, PhotosUI, Photos, UniformTypeIdentifiers. Ask before adding any dependency.
- Internal coordinate system: image pixels, origin top-left, y down, after applying EXIF orientation. Convert at the Vision and Core Image boundary and nowhere else (see `docs/ARCHITECTURE.md`).

## Commands

Run from the repo root. Verified on Xcode 26.5 / Swift 6.3 (2026-09-21).

```bash
# The main gate. Runs SpecKitTests, PlannerTests and FixtureTests on macOS.
swift test --package-path PassportKit
```

```bash
# Release is ~50x faster and is what the fixture suite should be timed with.
# The golden case takes 2.9 s in release and 141 s in debug.
swift test -c release --package-path PassportKit
```

```bash
# One suite, or one test by name.
swift test --package-path PassportKit --filter SpecKitTests
swift test --package-path PassportKit --filter "required head px"
```

```bash
# Build the app.
xcodebuild -scheme PassportPhoto -destination 'platform=iOS Simulator,name=iPhone 17' build
```

```bash
# Build against the iOS 18 deployment floor. Pin the OS: iPhone 16 has no 26.5 runtime here,
# and a bare `name=iPhone 16` resolves to OS:latest and fails to match a device.
xcodebuild -scheme PassportPhoto -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' build
```

```bash
# What destinations actually exist here.
xcodebuild -showdestinations -scheme PassportPhoto -project PassportPhoto.xcodeproj
```

```bash
# Debug PNGs written by FixtureTests (mask, crop overlay, final photo). Look at these.
open /tmp/passportkit-debug/
```

```bash
# Debug builds only: run a photo through the flow on launch, without tapping. Used to screenshot
# the real screens. The file must be inside the app container.
xcrun simctl launch <device> com.rohith.PassportPhoto -autoProcessPhoto <path-in-container>
```

Notes:
- **The app only works on a real iPhone.** Neither Simulator runtime can run Vision's models:
  iOS 26.5 throws `Vision Code=9 "Could not create inference context"`, and iOS 18.4 silently
  returns no faces. Both are reported in-app as a device limitation. See LESSONS 16. The Mac
  fixture suite is the real gate.
- **Run the app in Release when testing on a device.** Xcode's Run action defaults to Debug, which
  compiles PassportKit unoptimised: the same 24 MP photo takes ~141 s instead of ~2.9 s, which
  looks like a hang. Product → Scheme → Edit Scheme → Run → Build Configuration → Release.
- `PassportKit` builds for iOS 18 and macOS 15, so the fixture suite runs on the Mac. Several
  Vision requests are limited or behave differently in the iOS Simulator; the Mac run is the gate.
- `fixtures/photos/` and `fixtures/reference_output/` are gitignored. Tests that need them skip
  cleanly when they are absent.

## Working style

- Work milestone by milestone (`docs/PLAN.md`). Finish each with tests green and a short entry in `docs/PROGRESS.md` covering what changed, what was measured and what's still open.
- **Look at outputs, not just numbers.** Fixture tests write debug PNGs (mask, crop overlay with crown, chin and eye lines, final photo) to `/tmp/passportkit-debug/`. Open and inspect them. During prototyping, every metric passed while the output had a white streak across the eyebrows.
- If a threshold has to change to make a fixture pass, explain why in the commit message. If it's a new finding, add it to `docs/LESSONS.md`.
- Ask the owner before changing any value in `specs/`, adding dependencies, or doing signing or App Store work.
- `fixtures/photos/` and `fixtures/reference_output/` contain the owner's face, the latter as a finished identity-document photo. Both are gitignored. Tests that need them skip with a clear message if they're missing. Never copy those images anywhere else, and never commit them.
