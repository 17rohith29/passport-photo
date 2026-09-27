# App Store material

Everything needed for the listing, in one place. Nothing here is submitted automatically.

```
store/
  README.md        this file
  LISTING.md       name, subtitle, description, keywords, review notes
  PRIVACY.md       privacy policy, ready to host
  marketing/       finished screenshots to upload  (1320 x 2868)
  screenshots/     the raw simulator captures they are built from
```

## Upload these five

`marketing/`, in numbered order. They are written to read as one sentence rather than five
pictures of an app, because most people swipe the first two and stop:

| File | Headline | The beat |
|---|---|---|
| `01-your-photo.png` | The photo you already have | You do not need a new photo, or a shop |
| `02-measured.png` | Measured, not guessed | It is real measurement, not a crop tool |
| `03-honest.png` | And honest about the rest | The thing no competitor does |
| `04-print.png` | Then exactly how to print it | The part people actually get wrong |
| `05-countries.png` | Several countries, one tap | Free, no account, nothing uploaded |

Slides 2, 3 and 4 show **one part of a screen, enlarged**, not the whole screen. A full iPhone
screen is unreadable at the size these are browsed at, and the detail is the point in each case.
Slides 1 and 5 show the whole app, running off the bottom edge so it reads as a device in use.

1320 x 2868 is the 6.9 inch size. Apple scales it down for smaller devices, so this one set
covers every iPhone.

## The one that is missing

The result screen, with a real finished photo on it. Vision does not run in the Simulator, so it
can only be captured on a device. It is the most persuasive image the app has and it is worth
getting during testing.

To capture it: run on your iPhone, put it through a photo, and screenshot the result screen.
Send me the PNG and I will composite it the same way. Suggested caption:

> **Your photo, measured** / Head height, eye line and background, all checked

It would slot in as slide 02, pushing the others down, because a real finished photo is more
persuasive than any screen of text.

Two notes. A screenshot of a stranger needs their permission, so use your own face or someone
who has agreed. And set the status bar to 9:41 first if you want it to match the others:

```bash
xcrun simctl status_bar booted override --time "9:41" --batteryState charged --batteryLevel 100
```

That only works on the Simulator. On a device, just crop or accept the real status bar.

## Regenerating

The screenshots are generated, not drawn, by `tools/store-shot.swift`. After a UI change,
recapture with the Simulator and re-run it:

```bash
xcrun swiftc -O tools/store-shot.swift -o /tmp/store-shot
/tmp/store-shot raw.png out.png "Headline" "Subline"
```

The palette comes from the app icon: navy #2E3866 to #141936, amber #F7BC4C, and the icon's own
crop marks framing the device. Headlines auto-fit so a long one shrinks to fit two lines rather
than wrapping badly.

## Before you can submit

- [ ] Reserve the name in App Store Connect. "Exact ID Photo" is the choice; see LISTING.md for
      why, and for two fallbacks. Search cannot prove a name is free, only App Store Connect can.
- [ ] Host PRIVACY.md somewhere public and put the URL in App Store Connect
- [ ] A support URL, which can be the same page
- [ ] Test on a device, see docs/DEVICE-CHECKLIST.md
- [ ] Capture the result screenshot above

Already done: privacy manifest, export compliance, usage strings, icon, launch screen, and the
App Privacy answer, which is "no data collected" and was verified rather than assumed.
