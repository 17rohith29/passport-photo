# Exact ID Photo

An iOS app that turns a photo you already have into a passport or visa photo cut to the exact
size a given country requires. Everything runs on the device. There is no network code in the
app at all, so a photo cannot leave the phone even by accident.

Ten documents today: Australia, Canada, China, India, Japan (passport and visa), Russia, the
Schengen Area, the United Kingdom and the United States.

## What makes it different

Most apps in this category promise compliance. This one measures what it can and then **tells
you what it could not check**. Every document carries a list of the rules the authority states
that the app has no way to verify: how recent the photo is, what paper you print it on, whether
you are wearing glasses, whether a studio took it. A green verdict means the measurements pass,
never that an authority will accept the photo.

Where a country's own guidance argues against an app like this, that is quoted too. Australia's
passport office says it does not recommend using a mobile app; Canada rules out any photo
altered with software. Both appear in the app, before the user decides.

## How requirements are stored

Every country-specific number lives in `specs/*.json`. None of them are written in Swift. Each
spec records the official page it was read from, the date, a confidence level, and the rules the
app cannot enforce. Where a figure could not be confirmed first-hand, the spec says so and the
UI shows it: Russia's dimensions are marked "not verified first-hand" in the document picker,
because they are.

Adding a country means adding one JSON file. The schema is `specs/document-spec.schema.json`.

## Layout

```
PassportKit/          Swift package, platform-independent
  SpecKit/            spec loading, validation, geometry
  PhotoAnalysis/      Vision wrappers, image buffers, matte refinement
  PhotoPipeline/      the pipeline, checks, crop planning, rendering, export
PassportPhoto/        the SwiftUI app
specs/                one JSON file per document
docs/                 architecture, plan, the lessons file, App Store material
tools/                icon and screenshot generation
reference/python/     a prototype pipeline, kept as a behavioural oracle
```

## Building

Requires Xcode 16 or later and iOS 18.

```bash
open PassportPhoto.xcodeproj          # run on a device, see below
cd PassportKit && swift test          # 242 tests
cd PassportKit && swift test -c release   # the fixture suites need release, ~3 minutes
```

**Vision does not run in the iOS Simulator.** Face detection and segmentation fail there, so
anything past "import a photo" needs a real device. The app detects this and says so rather
than blaming your photo. Several debug launch arguments open individual screens for
screenshotting; see `DebugAutoRun` in `HomeView.swift`.

The photo fixtures the tests calibrate against are real people's faces and are not in this
repository. The suites that need them skip cleanly when they are absent.

## docs/LESSONS.md

The most useful file here. Forty-nine findings from building it, each one a bug that reached a
working state before it was caught, written so it does not happen again. A sample:

- a check whose threshold filters its own input can never fail, and one did, passing a pure
  black photo while reporting "darkest channel 255"
- stamping the wrong DPI into the export would have printed every photo 52% too large
- the camera's "raise the camera" and "lower the camera" cues were the wrong way round
- a fix applied to one mode and not the default is not a fix
- a tick is a claim that something was checked, so a rule nobody states must show no row at all

## Contributing

Adding or correcting a country is the most useful contribution. Two rules:

1. **Cite the authority's own page**, and quote it in the `says` field. Not a photo-service blog.
2. **Anything the authority states that the app cannot check goes in `notEnforced`.** A rule that
   is in neither the checks nor that list is the failure this project cares most about avoiding.

If a figure cannot be confirmed first-hand, say so in `status.notes` and set `confidence`
accordingly. An honest "not verified" is worth more than a plausible number.

## Licence

Apache 2.0. See `LICENSE` and `NOTICE`.

The licence covers the code. It does not grant rights to the app's name or icon.
