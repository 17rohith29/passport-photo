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
face in it, and invites them to pick another photo, none of which will ever work.
**Rule:** the Mac fixture suite (`swift test`) is the gate, and the app is only meaningfully
testable on a real iPhone. Vision failures, and `noFaceFound` when compiled for the Simulator,
are reported as a device limitation: a different headline, no "choose another photo" button and
no tips, because nothing the user does here will help.
**Test:** `PhotoSessionTests` drive the real flow on macOS, and
`PassportPipeline.isDeviceLimitation` is what the UI branches on.

## 17. A stage that throws needs a user-visible reason
The rejection screen originally showed failed *checks* only. When a stage threw instead, the
screen fell through to a bare "This photo can't be used." with nothing else on it, a dead end
that hid a Vision error completely.
**Rule:** `PipelineResult` carries `failureReason` (plain language) and `technicalDetail` (the
raw error, behind a disclosure). Never show the raw error as the headline, and never leave the
screen with no explanation.

## 18. A rule stated in different units gets silently dropped
Specs state the same rule in whatever unit the authority publishes: India gives head height in
millimetres, the EU gives it as "70-80% of the photograph", the US gives the eye line in
millimetres where India gives a fraction. Code that reads only one form does not fail loudly -
it reads `nil` and skips the rule.

This bit in three places at once, all found by adding a third country:
- `ComplianceChecker.headHeightCheck` read `passMM` only, so for the Schengen spec the **head
  height was never checked at all**, the one rule the Commission actually publishes.
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
that threshold **rejected 12 of them**, people with visibly closed mouths.

Two things were wrong. The metric normalised the inner-lip gap by outer-lip **width**, which is
yaw-sensitive: turning the head foreshortens the lips horizontally and inflates the ratio, so
profile shots scored as wide-open mouths. Normalising by interocular distance instead removed
that, and tightened the owner's own set to 0.015-0.030.

But it did not fix the real problem: **the populations overlap.** Vision's inner-lip contour has
thickness even when the lips touch, so a closed mouth reads up to 0.096 (a frontal one at 0.077)
while the owner's parted-lip photo reads 0.062. No threshold separates them. A pixel-based
attempt, looking for teeth or cavity inside the lip ring, did not separate them either and was
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
three photos. **Two of the three were visibly broken**, one kept a rectangular slab of the
original dark photo with hard straight edges, another had blue fringing and a blue patch on the
shoulder, and both scored **99%+ pure background with faceIntegrity passing**.

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
the wall's colour survives as a fringe, a blue-backdrop portrait came out with blue edging along
the hair.

The obvious generalisation, clean rim pixels close to *this photo's* wall colour, **was tried and
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
`.balanced`, and this is an **Objective-C exception, so Swift cannot catch it**, the app dies on
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

## 24. Swift traps on bad numbers; it does not throw
A crash hunt across the shipping code found four live trap sites. None of them would ever have
surfaced as an error, they kill the process:

- **`background.minChannelValue` was never validated.** The JSON schema bounds it 0-255 but
  `Codable` does not enforce that, and the value is converted straight to `UInt8` when a finished
  photo is checked. A country file with `minChannelValue: 300` would have crashed the app. The
  whole architecture is "countries are data", so a data file must not be able to do that.
  `validate()` now bounds it, along with sizes, dpi, copies, and a head height that must fit
  inside its own photo.
- **`GrayImage.at()` indexed out of bounds on an empty image.** It clamps to `width - 1`, which
  is -1 when the image is empty, and degenerate crops legitimately return empty images, so every
  caller could reach it.
- **`ImageMetrics.clamp` converted a NaN rect with `Int(_:)`.** A face whose landmarks collapse to
  a point divides by a zero width and produces exactly that NaN.
- **`RGB.bytes` did not clamp** before `UInt8(_:)`, and the type has a public memberwise
  initialiser that polices nothing.

`ChinRefiner` and `CrownFinder` also convert landmark coordinates to `Int` and now refuse
non-finite or absurd input rather than reaching the conversion.

**Rule:** anything that becomes an `Int`, a buffer length, an array index or a `ClosedRange` needs
a finite-and-in-range guard first, however impossible the bad value looks. A degenerate Vision
result is not impossible.
**Test:** `SpecCrashSafetyTests` and `GeometryCrashSafetyTests` feed NaN, infinity, zero,
negative and absurd values to every such site. Two of them crashed the test process when first
written, which is exactly what they are for.

## 25. A fullScreenCover with no background is an overlay
Reported from the device: "the next screen seems to be an overlay of the first screen". It was.
`ProcessingView` is rooted in a `VStack` and the result and rejection screens in a `ScrollView`;
neither fills the frame or paints a background, so the cover was transparent and Home showed
straight through it.
**Rule:** anything presented in a `fullScreenCover` or `sheet` gets
`.frame(maxWidth: .infinity, maxHeight: .infinity)` and an explicit background. Applied once on
the `Group` inside `SessionFlow`, which covers all three screens.

## 26. GOV.UK's own two pages disagree about the shape of a UK photo
The printed rules say 45 mm by 35 mm, 7:9. The digital rules say "at least 600 pixels wide and
750 pixels tall", 4:5. Rendering a 7:9 crop into a 600x750 frame stretches every face about
2.9% wider, and nothing in the pipeline would have complained, because both numbers came from the
spec.
**Rule:** `gb-passport` outputs **700x900**, which is exactly 7:9 and still clears both stated
minimums. When an authority's own figures disagree, satisfy the constraint that is checkable
(the minimums) and keep the geometry that is physical (the printed aspect).
**Test:** `UKPassportSpecTests` asserts the pixel aspect equals the millimetre aspect, that the
minimums are still met, and that the naive 600x750 reading really would have been wrong.

## 27. A rule you cannot check must be written down, not dropped
Adding four more documents surfaced rules the app has no way to measure: Australia's 200 gsm
dye-sublimation paper, the UK's "taken in the last month", Canada's "taken in person by a
commercial photographer", China's head WIDTH of 15-22 mm, and glasses everywhere. Left alone,
each of those would have vanished, not in the checks, not on screen, and a green verdict would
have implied full compliance.
**Rule:** `status.notEnforced` lists them, the requirements sheet shows them under "What we can't
check", and a test asserts every document declares at least one. Any document stating a glasses
or ears rule must admit it is unchecked, because neither is ever measured.
**Test:** `AllDocumentsTests.everyDocumentDeclaresItsGaps`.

## 28. Canada forbids exactly what this app does
canada.ca requires "an original photo that isn't altered or edited in any way" and rules out
"photo editing software, filters, and AI tools". This app replaces the background, which is an
edit. The UK and Australia say similar things less absolutely.
**Rule:** say so plainly in `background.editingRisk` and in `notEnforced`, rather than shipping a
green tick that the issuing authority would reject on sight. The app is genuinely useful for
checking framing before paying a studio; it is not a substitute for one in Canada.

## 29. A size range is not a size
Australia states 35-40 mm wide by 45-50 mm high, a range, where the schema has a fixed
`sizeMM`. Extending the schema would have been the obvious move and the wrong one: the app must
output ONE size regardless, and the head band of 32-36 mm is fixed whatever the photo size, so
the smallest legal size frames the head most tightly and satisfies every larger one.
**Rule:** output 35 x 45 mm, the smallest size in Australia's range and the standard booth size,
and record in the spec's notes that the range exists and why this size was chosen. Reach for a
schema change only when a country needs a rule the schema genuinely cannot express.

## 30. A check that is skipped reads exactly like a check that passed
The output verifier ran `headHeight` and `topMargin` inside `if let crown = CrownFinder.find(...)`.
When segmentation threw, or the crown could not be found in the finished file, those checks were
simply absent from the array, and `Verdict.from` saw no failures and said "meets requirements".
The most important rule in the app could vanish silently, and the measurement overlay still drew
the planner's numbers on top, so it looked measured.
**Rule:** when a check cannot be performed, append a failing result saying so. Never let the
absence of a check be indistinguishable from its success. This is LESSONS 18's failure shape one
layer up: there, a spec form that was not read; here, a check that was not run.
**Test:** `ComplianceChecker.unmeasuredHeadCheck`; the whole fixture set still passes unchanged,
which is what proves it does not fire on photos that work.

## 31. DPI metadata is an instruction to a printer, not a label
The digital JPEG was stamped with `photo.print.dpi` (300). A 630x810 px file at 35x45 mm is
actually 457 ppi, so any lab or print dialog honouring the embedded value would have produced a
53x69 mm photo, 52% too large, while the app's own advice told the user the file was already
the right size.
**Rule:** the digital file carries `SpecGeometry.digitalDPI` (`pxPerMM * 25.4`), derived the same
way as every other geometry number. `photo.print.dpi` describes the print tiles and nothing else.
**Test:** `ExportMetadataTests` reads `kCGImagePropertyDPIWidth` back out of the encoded bytes and
checks the file would print at the millimetres the spec states.

## 32. Finite and positive is not a bound
`checkPositive` accepted 1e30. It is finite, it is positive, and `Int(1e30)` traps on overflow
just as hard as `Int(nan)` does, reachable from a `specs/*.json` that passes `validate()`, through
print-tile sizes, buffer lengths and the printing advice. The same gap sat in `CrownFinder`,
`ChinRefiner` and `GrayImage.cropped`, which all checked `isFinite` and then converted to `Int`.
**Rule:** anything that becomes an `Int`, an index or an allocation needs a magnitude bound, not
just a finiteness check. LESSONS 24 said "finite and in range"; only the first half was implemented.
**Rule:** a spec must also not be able to contradict itself into rejecting every photo, a
`colorHex` darker than its own `minChannelValue` fails every correctly rendered background and then
blames the user for it. `validate()` rejects that pairing.

## 33. A capture cue that fires on a good photo is worse than no cue
Live background advice looked easy: sample the wall beside the head, flag it if it is dark or
busy. The dark half worked. The busy half did not: the first threshold, chosen from synthetic
walls where the right answer was known by construction, would have nagged **13 of the 14 real
fixture photos**. Real walls are not flat, they carry shadow and gradient, and the fixture with
the highest "variation" turned out to be a lighting problem (it also has the worst cheek
imbalance in the set), not a patterned wall.
**Rule:** a threshold measured only against synthetic input has not been measured. Run it over
the real photos before it says anything to a user.
**Rule:** when a metric does not separate, ship silence rather than a cue. The reading is kept
and tested; no cue is emitted until there is labelled data showing where the line is.
**Test:** `FrameQualityCalibration` asserts no real attempt is ever told its wall is too dark,
and that the dark threshold keeps margin under the darkest real photo.

## 34. Glasses detection: the API exists, but not for us
`VNClassifyFaceAttributesRequest`, `FaceObservation.Attributes.Glasses` (`.none`,
`.prescription`, `.sunglasses`) and `VNGenerateGlassesSegmentationRequest` are all present as
symbols in the iOS 26.5 Vision binary, and none of them are in the public SDK headers or
importable from Swift at any deployment target. They are SPI.
**Rule:** do not reach for them. Shipping against private API risks rejection and breaks on any
OS update. `appearance.glassesAllowed` stays in `status.notEnforced` until either Apple makes
this public or we can show a heuristic separates on labelled data.
**Note:** if a heuristic is attempted, it may only ever WARN on detection. "No glasses detected"
must never count as a pass, a false negative leaves the honest status quo, while a false pass
is the over-promise non-negotiable 6 forbids.

## 35. A rule every authority states, that nothing checked, that no spec admitted
All eight authorities require a colour photo, India's booklet says "Do not paste black and white
photographs", China's says "It must be a color photo", GOV.UK says "in colour". Nothing in the
app measured colour, `CheckID` had no case for it, and seven of the eight `notEnforced` lists did
not mention it. A greyscale scan passed every other rule and earned a green "meets requirements".
`AllDocumentsTests.everyDocumentDeclaresItsGaps` did not catch it: it asserts `notEnforced` is
non-empty and special-cases glasses and ears, but never enumerates the rules a spec states.
**Rule:** where a stated rule is cheap and unambiguous to measure, measure it rather than
declaring it unenforceable. Colour is the clearest case in the app: across the fixtures a colour
face reads 0.39-0.52 saturation and the same photo desaturated reads exactly 0.00, so the
threshold sits in a gap nothing realistic can fall through.
**Rule:** "could not measure" must never share a value with a real reading. `faceSaturation`
first returned `0` for an unmeasurable face, which the check read as "black and white" and would
have rejected a perfectly good colour photo. It returns `nil`, and the check is skipped.
**Test:** `ColourCheckTests`, including the pipeline refusing a desaturated fixture end to end.

## 36. `fixability: .automatic` is a promise the code has to keep
`fileSizeCheck` hard-coded `.automatic` for both ends of the range, but `JPEGExporter` only steps
quality DOWN to satisfy `range.max`, nothing raises quality or pads to satisfy `range.min`. An
undersized file therefore told the user processing would handle something no code in the pipeline
can do. Not reachable with today's specs, which is why it survived.
**Rule:** `.automatic` means a stage actually fixes it. If no stage does, it is `.retakeRequired`
and the user gets told what to do instead.

## 37. The wall estimate is computed from the refined matte, so every matte change re-tunes colour everywhere
The owner reported hair being handled badly. Measured on their output (827x1063, #F0F0F0): **641
backdrop-coloured pixels punched INTO the subject**, concentrated at rows 80-84, the crown. The
cause is `cleanRim`, which clears any rim pixel that is bright and low-saturation, and sets alpha
to exactly 0. Hair sheen is bright and low-saturation, so every highlight on a dark strand is
read as wall.

The obvious repair, put back small enclosed pockets that cannot be walked out to the border -
**was tried and reverted, twice**. First restoring any pocket, then only fully opaque ones, then
only those outside the face region entirely: all three put `faceIntegrity` at **15.33%** on
IMG_0009 and **0.47%** on IMG_0012, which is the same number LESSONS 21 records for the last
attempt at this.

The reason is not the repair. `Renderer.estimateBackgroundColour` samples the source wherever
`matte < 0.05`, so changing which pixels are transparent changes the estimated wall colour, which
feeds `unmix` for **every** pixel including the face. A repair confined to hair still moved the
face, because the coupling is global. Hole counts were byte-identical across the attempts while
faceIntegrity swung 15 points, which is how this was finally diagnosed.
**Rule:** measure `faceIntegrity` on IMG_0009 *and* IMG_0012 for any matte change, not just
IMG_0012, IMG_0009 is 30x more sensitive.
**Rule:** a real fix has to break the coupling first, estimate the wall from the *unrefined*
matte, or from a region fixed before rim cleanup runs, before touching `cleanRim` at all.
**Fixed, and the diagnosis was the fix.** Two changes, in this order:
1. `estimateBackgroundColour` now takes the wall from the top corners of the crop, wall in any
   valid passport framing, by median, and never consults the matte. That breaks the coupling.
   It is also simply better: rim pixels carry subject bleed, so letting them define the wall
   biased the estimate towards the hair it was supposed to be unmixing out.
2. `cleanRim` now requires a pixel to sit in a backdrop *region* before clearing it: most of its
   neighbours must look like backdrop too. Wall is a region; a highlight on a strand is not.
   This is a neighbourhood test, not the colour-distance test LESSONS 21 forbids.

With the coupling broken, step 2 costs nothing: `faceIntegrity` is **0.00%** on every fixture,
and punched holes fall from 0.0239% to **0.0157%** worst case (IMG_0013 improves ten-fold).
Neither change works without the other, step 2 alone put IMG_0009 at 0.66%, over the 0.5% limit.
**Rule:** when a local change moves a distant number, look for a global estimator reading the
thing you changed, before tuning thresholds. Three attempts were spent tuning what was never a
threshold problem.

## 38. The background checks were written for a background we painted
Four authorities rule out an edited photo outright, Canada ("isn't altered or edited in any
way"), the US, GOV.UK and Australia, and the app replaces the background on every run. So a
`keep` mode was added: crop, level and scale, composite nothing.

The first run of it failed every strict document, and the reason was instructive. The background
check counts pixels **exactly equal** to the spec colour. That is a test for "did we paint this",
not "is this wall acceptable", a real wall is never one exact value, so it scored 0.0% pure.
`sideMarginPurity` has the same problem: it is a cut-out integrity signal (LESSONS 20) and means
nothing when nothing was cut out.
**Rule:** a check written against synthetic output is not a check of the real thing. In `keep`
mode the wall is judged on its own terms, light enough, by its darkest channel, and the failure
message talks about the wall rather than blaming separation that never happened.

**Why `replace` is still the default.** Measured on the fixtures, a real wall reads **173-211** on
its darkest channel where these specs demand **245**. Defaulting to `keep` would reject nearly
everyone, including the golden photo. So `keep` is offered explicitly on the documents that
forbid editing, with the reason stated, and when the wall does not pass, the rejection screen
offers the edit as the way out. Both paths are honest; neither is chosen for the user.

## 39. A check whose threshold filters its own input always passes
The keep-mode wall check read: is the darkest pixel of the backdrop region at or above
`minChannelValue`? But `backdropRegion` admits **only** pixels already at or above that value. So
the test could not fail while the region was non-empty. What it actually asked was "is there any
bright blob touching a top corner".

Measured on a 1200x1680 Canada output: a uniform 180-grey wall, dead centre of the 173-211 band
LESSONS 38 measured on the real fixtures, failed correctly with an empty region, and the *same
wall with a 12x12 bright corner* (144 px out of 2,016,000) passed, reporting "your wall reads
100% brightness". A window highlight or a lamp on a wall/ceiling junction is enough, and
LESSONS 33 already records that real walls carry shadow and gradient.

The honest metric existed in the repo the whole time: `RealWallCalibration` takes the **median**
of the top band, which is where the 173-211 figure came from. The check never adopted it.
**Rule:** when a check consumes a region selected by the same threshold it then tests, it is a
tautology. Ask what the metric could possibly report other than a pass.
**Rule:** prefer the median over an extreme for "what is this surface". A minimum answers "is
there one good pixel"; a median answers "what is the wall".
**Test:** `WallCheckTests` runs a 180 wall with 0, 12 and 40 px bright corners and requires all
three to fail, and requires the reported brightness to track the wall's real tone.

## 40. A mode that promises not to paint must not paint the parts it cannot see
`Renderer` fills out-of-source pixels with the spec colour, which is right when the background is
being replaced and wrong when it is being kept. Measured on a 3000x4000 source with the crown
near the top: **15.12% of the kept output was exactly #FFFFFF**, and because that painted band
reaches the top corners, it also guaranteed the wall check above passed. A dark wall plus an
overhanging crop was a silent green verdict on a photo the app had invented a sixth of.
**Rule:** in `keep` mode a crop that runs past the edge of the photo is a rejection, not a fill.
There is nothing there to keep, and inventing it is the exact edit the mode exists to avoid.

## 41. Fixing a bug on the new path and leaving it on the default path
LESSONS 39 (the tautology) and 40 (painting what it cannot see) were both found while building
`keep` mode, and both fixes landed **only in the `keep` branch**. `replace` is the default for
all eight documents, so the bugs stayed live on the path every user takes, while the notes said
they were fixed.

Measured on the default path, before this: a photo filled with **pure black**, with a 40x40 white
patch in one corner and two white side strips, passed `background` for every wall tone from 0 to
244, reporting **"darkest channel 255"** every time. The same images failed correctly in `keep`.
End to end, a dark slab of the original room inside a thin painted border, **74.4% of the photo
below the spec's floor**, returned `meetsRequirements` with all ten output checks passing. That
is LESSONS 20's photo again, and `sideMarginPurity`, the fix written for LESSONS 20, is evaded
because it samples only the outer `width/14` px strips that the painted border covers.
**Rule:** when a bug is found in one mode, check the other mode before writing the lesson. A fix
that does not run on the default path is not a fix.
**Rule:** `sideMarginPurity` samples two thin strips, so any fake that covers those strips beats
it. What a real photo cannot fake is that **the subject runs off the bottom of the frame**, head
and shoulders always do, and a slab floating inside a border touches no edge. That, plus a
backdrop-coverage floor calibrated at 30% against real outputs measuring 40-60%, is what catches
it now.

## 42. A check downstream of the thing it measures is measuring itself
`centeringCheck` measured the eye midpoint against the frame centre. `CropPlanner` sets
`rect.x = eyeMidpointX - cropWidth/2`, so the eye midpoint lands at the output centre **by
construction**. Measured: with the eyes shifted 180 px off the head's own centre, the head sat
19.8% off centre and touched the right frame edge, and the check reported **"0.00% off centre"**
against "under 2%". It now measures the head contour's centre, which is what the rule is about.
**Rule:** ask what the checked value is computed *from*. If the planner placed it, checking it
confirms arithmetic, not the photo.
**Also:** the app's only edge test was `CrownFinder.touchesTopEdge`. A head running off the left,
right or bottom of the source was never noticed, a face sliced flat against the frame edge
produced a green verdict with all ten output checks passing. There is now a check for it.

## 43. Calibrating against the fixture set is calibrating against one person
LESSONS 33 warned that a threshold measured only on synthetic input has not been measured. This
is the mirror image, and it bit immediately: `minBackdropCoverage` was set to 0.30 from four
fixture photos, which are one person, one wall, one head of hair.

Measured against synthetic subjects across all eight specs, varying head width, hair volume and
shoulder width independently:

```
cn-visa      big hair        29.5%  FAIL
ca-passport  wide face+hair  26.6%  FAIL
gb-passport  all three       30.0%  FAIL
ru-visa      all three       30.0%  FAIL
```

A China visa applicant with ordinary hair volume would have been rejected. That is a worse
failure than the false pass the check was written to stop: a false pass yields a bad photo the
user can retake, while this refuses a good photo and explains nothing.
**Rule:** for any threshold about a *person*, vary the person, width, hair, build, not just the
lighting and the wall. The fixture set cannot tell you what a different body does.
**Rule:** when several signals guard one rule, work out which is doing the discriminating. Here
the top-band median and "the subject reaches the bottom edge" do it, and neither penalises a
larger person; coverage only needs to reject a region pieced out of a corner patch, which
measured 4.6%. A backstop set near the realistic range is a false-rejection machine for no gain,
so it sits at 0.15, ten times the fake it catches, ten points clear of the tightest real case.
**Test:** `NewCheckAuditTests` asserts both directions, and requires eight points of MARGIN, so a
future tightening cannot quietly reintroduce this.

## 44. Every guard protects the path it was written for
LESSONS 41 said a fix applied to one mode and not the default is not a fix. The same shape came
straight back in the save-and-finish flow, three times in one commit, and all three were in code
written two days after that lesson:

- `PhotoSaver`'s `guard state != .saving` exists because "a second tap wrote a second asset with
  nothing to tell the user". The new `saveOther` called `saver.reset()` first, which disarms it.
  The comment justifying the reset was also wrong: `saveToPhotos` sets `.saving` first, which is
  already a change, so `onChange` fires without it.
- `otherVariant(after:)` correctly refuses a format with no bytes behind it, but the segmented
  picker and `currentData`'s `printSheetJPEG ?? digitalJPEG` fallback did not, so selecting
  "Print sheet" on a document that produced none saved the single photo under a `-print-4x6`
  name with cut-and-measure instructions attached.
- `HomeView` carries a comment about two presentations fighting in one transaction, and the fix
  there was to defer to `onDismiss`. `saveOther` dismissed the Saved sheet and presented the file
  exporter in the same update. A dropped presentation would also have left `exporting` stuck
  true, killing every later Save to Files for the rest of the session.

**Rule:** when adding a second caller to an existing operation, re-read every guard that
operation has and ask which path it was written for. A guard is not a property of the function;
it is a property of the route through it.

## 45. A fallback that substitutes one output for another is a mislabel, not a kindness
`currentData` returned `printSheetJPEG ?? digitalJPEG`, so a missing print sheet quietly became
the single photo, saved under a print-sheet filename with "the sheet holds 6 photos, cut 2 out"
printed beside it. The fallback looks defensive and is the opposite: it produces a plausible
wrong answer where nil would have produced an honest empty state.

Related, same flow: a completion that recorded `savingVariant ?? variant` fell back to whatever
the user was *looking at* rather than what was *written*, so switching the picker during a save
logged a single photo as a print sheet.
**Rule:** never default one artefact to a different artefact. If the thing asked for does not
exist, say so and disable the control that offers it.
