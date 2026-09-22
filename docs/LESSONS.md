# Lessons from prototyping

Each lesson comes from a real failure while building the Python reference on the owner's photos (September 2026). The "Test" line says how to keep it fixed.

## 1. Landmark chins sit inside beards
dlib's chin point landed 3.7-5% of head height above the true chin on a bearded face. That's about 1.5 mm on the print, enough to push head size out of spec. Vision's contour may have the same bias, so measure it.
**Rule:** start from the landmark chin and walk down a centre strip (about ±10% of face width) until beard texture (local Laplacian energy) falls to the smooth-neck level. For clean-shaven faces, fall back to the strongest light-to-dark edge (chin into the under-chin shadow). See `reference/python/chin.py`.
**Test:** IMG_0012 chin within the tolerance in `fixtures/expected.json`.

## 2. Flyaway hair inflates the crown
Stray strands sit about 0.2 mm above the hair mass. Taking the first mask pixel as the crown makes the head measure taller than it is.
**Rule:** crown = first row where the mask spans at least 8% of face width.
**Test:** IMG_0012 crown within tolerance.

## 3. The photo is the product
A webcam shot and photos taken across the room couldn't be fixed. Even EDSR super-resolution only partly recovered them. Shooting closer fixed everything.
**Rule:** reject when head height in pixels is below the output's required head pixels. Never upscale.
**Test:** IMG_0004-0007, 0011, 0015 and 0016 are rejected for `resolution`.

## 4. Resample once, with area averaging
Upscaling with the wrong filter, and building the print sheet by shrinking an already-resized image, both visibly blurred results.
**Rule:** measure and composite at native resolution, then do one area-averaging downscale per output. The print tiles are rendered from the source, not from the 630x810 file.

## 5. Lighting can't be fixed afterwards, and the metric is fragile
IMG_0010 was the sharpest shot but side-lit, with cheeks 12.6-18.9% apart depending on where the patches sat. The same photo can score 2% or 11% under two patch placements (IMG_0013).
**Rule:** one documented patch method, calibrated on fixtures, with a warn band (spec: warn above 8%, fail above 12%). Check it at the input gate.
**Test:** IMG_0010 rejected for `lighting`. IMG_0013 and 0014 may be pass or warn, but must not crash or reject for anything else.

## 6. Yaw: don't trust a generic 3D fit
`solvePnP` with a generic face model returned -21° to +12° on photos that looked frontal. Half-face asymmetry suggested about 5° of turn in all nine new photos and about 1-2° the other way in the older set. That points at the phone being slightly off to one side.
**Rule:** use Vision's yaw and pitch. Warn above 5° (ISO/IEC 19794-5), fail above 8°. Record Vision's value for IMG_0012 in `docs/PROGRESS.md`; the Python estimate was 5.5° ± 2°.

## 7. Wall fragments survive segmentation
A grey rim, and bits of the ceiling light and a wall vent, stayed attached to the silhouette.
**Rule:** clean up only the outer rim: low-saturation, bright pixels within the edge band, never the silhouette core.

## 8. Mask seams let cleanup whiten the face
A seam in the mask along the eyebrows let the rim cleanup paint a white streak across the brows. Every metric still passed.
**Rule:** fill interior holes in the silhouette before any edge processing. The `faceIntegrity` check (no pixel inside the face oval turned near-white) is mandatory on every output.
**Test:** `faceIntegrity` passes on every accepted fixture, and debug PNGs are inspected by eye.

## 9. Edge band width: narrow on skin, wide in hair
A hard mask gave stair-stepped edges. A uniformly wide matting band let white bleed into the jaw.
**Rule:** the band width varies with y: wide above the brow line (hair), narrow below it (skin, shirt), with a smooth transition.

## 10. Sharpen the subject only
Unsharp masking on the whole image drew dark halos along the silhouette and grey noise in the background.
**Rule:** sharpen only where alpha is above 0.02, force background to the spec colour, and revert the 1-2 px anti-aliased rim to the unsharpened value. Two-stage unsharp looked natural at 630x810: (radius 1.3, amount 0.28) then (radius 0.8, amount 0.32). CLAHE was rejected because it looked like a beauty filter.

## 11. The spec itself is disputed
India head height: ICAO Doc 9303 gives 32-36 mm (70-80%). Several photo-tool sites say "80-85%" or 36-38 mm. One site states both, which is self-contradictory. The photo PDF VFS links is the stale 2x2 in format.
**Rule:** target 36.0 mm, the only value inside every range. Keep sources, `lastVerified` and a confidence field in the spec, and show them in the UI.

## 12. Edited backgrounds may be rejected
Unofficial sources claim the Passport Seva portal detects AI-replaced backgrounds. This is unverified.
**Rule:** v1 tells users plainly that the background was replaced and that the portal upload is the real test. The capture milestone will guide users to a genuinely white wall so processing becomes light cleanup.

## 13. A validator that reuses the planner's measurements can't find the planner's mistakes
**Rule:** `ComplianceChecker` re-runs face analysis and crown/chin detection on the output image. A second, independent chin method is a stretch goal.

## 14. Printing
**Rule:** a 4x6 in sheet at 300 dpi with 413x531 px tiles (35x45 mm), grey cut guides, and printed instructions: print at 100%, no auto-crop or enhance, measure one photo with a ruler. Glossy or matte photo paper are both fine.

## 15. Other small things
- HEIC from iPhone carries EXIF orientation. Apply it before landmarks.
- Very close shots (IMG_0010, about 0.5 m) add perspective distortion and side light. The capture milestone should aim for about 1.5 m with the 2x lens.
- A visible necklace is allowed. It's not a defect.

## 16. The iOS Simulator cannot run this pipeline at all
Both installed Simulator runtimes fail, and they fail *differently*, which is what made it
confusing:
- **iOS 26.5:** every Vision request throws `VisionError.requestCancelled` wrapping
  `Vision Code=9 "Could not create inference context"`. It fails on the very first
  `DetectFaceLandmarksRequest`, before any photo measurement happens.
- **iOS 18.4:** Vision runs but returns **zero face observations** for a photo that macOS detects
  fine, which is indistinguishable from a genuine "no face in this photo".

The second is the dangerous one: untreated, the app tells the user their clear portrait has no
face in it, and invites them to pick another photo — none of which will ever work.
**Rule:** the Mac fixture suite (`swift test`) is the gate, and the app is only meaningfully
testable on a real iPhone. Vision failures, and `noFaceFound` when compiled for the Simulator,
are reported as a device limitation: a different headline, no "choose another photo" button and
no tips, because nothing the user does here will help.
**Test:** `PhotoSessionTests` drive the real flow on macOS, and
`PassportPipeline.isDeviceLimitation` is what the UI branches on.

## 17. A stage that throws needs a user-visible reason
The rejection screen originally showed failed *checks* only. When a stage threw instead, the
screen fell through to a bare "This photo can't be used." with nothing else on it — a dead end
that hid a Vision error completely.
**Rule:** `PipelineResult` carries `failureReason` (plain language) and `technicalDetail` (the
raw error, behind a disclosure). Never show the raw error as the headline, and never leave the
screen with no explanation.

## 18. A rule stated in different units gets silently dropped
Specs state the same rule in whatever unit the authority publishes: India gives head height in
millimetres, the EU gives it as "70-80% of the photograph", the US gives the eye line in
millimetres where India gives a fraction. Code that reads only one form does not fail loudly —
it reads `nil` and skips the rule.

This bit in three places at once, all found by adding a third country:
- `ComplianceChecker.headHeightCheck` read `passMM` only, so for the Schengen spec the **head
  height was never checked at all** — the one rule the Commission actually publishes.
- The requirements sheet read `passMM` only, so Schengen showed **no head-height row**.
- It read `eyeLine.fromBottomFraction` only, so the US showed **no eye-line row**, and compared
  `colorHex == "#FFFFFF"`, so Schengen showed **no background row**.

**Rule:** resolve through `HeadHeightBand.inMM(spec:)` and `CropPlanner.eyeLineBand(spec:_:)`,
never by reading one field. Never compare a spec value to a literal to decide whether to show it.
**Test:** `SpecRenderabilityTests` walks every file in `specs/` and asserts each one resolves a
head band, an eye line, geometry and a parseable background, so a new country cannot be added
with a rule that silently does not apply.

## 19. One face is not a calibration set
`GateCalibration.maxMouthOpenness` was 0.070 because it split two of the owner's photos:
IMG_0009 (lips parted, 0.083) from IMG_0016 (0.059). Measured against 17 third-party portraits,
that threshold **rejected 12 of them** — people with visibly closed mouths.

Two things were wrong. The metric normalised the inner-lip gap by outer-lip **width**, which is
yaw-sensitive: turning the head foreshortens the lips horizontally and inflates the ratio, so
profile shots scored as wide-open mouths. Normalising by interocular distance instead removed
that, and tightened the owner's own set to 0.015-0.030.

But it did not fix the real problem: **the populations overlap.** Vision's inner-lip contour has
thickness even when the lips touch, so a closed mouth reads up to 0.096 (a frontal one at 0.077)
while the owner's parted-lip photo reads 0.062. No threshold separates them. A pixel-based
attempt — looking for teeth or cavity inside the lip ring — did not separate them either and was
removed rather than left in half-working.

What *is* separable is clearly-open from closed: closed tops out at 0.096, clearly-open starts at
0.156.
**Rule:** `mouthClosed` warns above 0.050 and fails only above 0.130, in that gap. A false
rejection is worse than a missed warning here: the user cannot argue with the app, and the
passport portal will catch a genuinely open mouth anyway.
**Consequence:** IMG_0009 moved from `reject` to `borderline` in `fixtures/expected.json`. That
is a change to the owner's ground truth, recorded in the case's own note and reversible.
**Test:** `ThresholdCalibrationTests` measures the third-party set and prints the distribution,
so the next threshold change is judged against a population rather than one face.

## 20. Numeric checks pass while the cut-out is mangled
Running 118 third-party portraits through the whole pipeline (not just the metrics) produced
three photos. **Two of the three were visibly broken** — one kept a rectangular slab of the
original dark photo with hard straight edges, another had blue fringing and a blue patch on the
shoulder — and both scored **99%+ pure background with faceIntegrity passing**.

The background check measured purity *inside* the backdrop region connected to the top corners.
When the cut-out fails, that region is **small but perfectly pure**, so it sails through. This is
LESSONS 8 in a new place: the metric was measuring the part that was fine.
**Rule:** also require the narrow strip down each side, level with the head, to be background. A
correctly framed passport photo always has clear space either side of the face; a mangled cut-out
does not. The worst of the three is now rejected.
**Test:** `CalibrationPipelineTests` runs the whole third-party set and reports what it refuses
and why, and asserts that nothing accepted misses its own head-height band.

## 21. The rim rule only ever worked for a pale wall
LESSONS 7 says to clean the outer rim of "low-saturation, bright pixels". That was written for the
owner's grey wall and it only matches a pale wall. Against a saturated backdrop it never fires, so
the wall's colour survives as a fringe — a blue-backdrop portrait came out with blue edging along
the hair.

The obvious generalisation — clean rim pixels close to *this photo's* wall colour — **was tried and
reverted**. Against a near-white wall, "close to the wall colour" also matches bright skin: it
wiped out IMG_0012's face entirely (faceIntegrity 100% near-white). Restricting it to saturated
walls still damaged the face at 0.47%, above the 0.5%... below the limit but a clear regression
from 0.00%, so it went back.
**Rule:** the fringe on coloured backdrops is a known limitation, not a solved problem. A real fix
needs per-pixel colour unmixing against a local background estimate, not a global colour-distance
test. **Do not reintroduce a colour-distance rim rule without checking faceIntegrity on IMG_0012**,
which is the test that caught it both times.

## 22. AVCapturePhotoOutput crashes if you ask for more quality than you allowed
`settings.photoQualityPrioritization = .quality` raises

    *** -[AVCapturePhotoOutput capturePhotoWithSettings:delegate:] settings.photoQualityPrioritization
        must not be higher than self.maxPhotoQualityPrioritization

unless `photoOutput.maxPhotoQualityPrioritization` has been raised to match. It defaults to
`.balanced`, and this is an **Objective-C exception, so Swift cannot catch it** — the app dies on
the first shutter press. With auto-capture on it fires by itself, so the whole capture screen
looks broken rather than one button.
**Rule:** set `maxPhotoQualityPrioritization` on the output during session configuration, before
the session runs, and clamp the per-request value to the output's ceiling anyway.

## 23. A capture delegate that drops failures leaves a dead shutter
`guard let data = photo.fileDataRepresentation() else { return }` discards both a nil payload and
the delegate's `error`, so a failed capture did nothing at all: no photo, no message, and the
shutter stayed live-looking forever.
**Rule:** the delegate always calls one completion path that clears the in-flight flag, and a
failure surfaces an alert. Capture is also guarded so the shutter and auto-capture cannot fire
together, and cancelling during the permission prompt no longer starts the session behind a
dismissed screen.
