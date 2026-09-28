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
| `02-measured.png` | Measured, not guessed | A real finished photo, measured on screen |
| `03-rules.png` | Every rule, checked | It is measurement, not a crop tool |
| `04-honest.png` | And honest about the rest | The thing no competitor does |
| `05-print.png` | Then exactly how to print it | The part people actually get wrong |
| `06-countries.png` | Several countries, one tap | Free, no account, nothing uploaded |

Slides 2 to 5 show **one part of a screen, enlarged**, not the whole screen. A full iPhone
screen is unreadable at the size these are browsed at, and the detail is the point in each case.
Slides 1 and 5 show the whole app, running off the bottom edge so it reads as a device in use.

1320 x 2868 is the 6.9 inch size. Apple scales it down for smaller devices, so this one set
covers every iPhone.

## The device screenshot

`screenshots/6-result.png` is the result screen, captured on an iPhone 15. It cannot be made
here: Vision does not run in the Simulator, so this screen is unreachable on this machine.

It is currently a **downscaled copy at 923 x 2000**, and slide 02 upscales it about 1.3x to fill
the panel. It holds up, but a full-resolution capture (1179 x 2556 on an iPhone 15) would be
visibly sharper on the one slide that matters most. Worth replacing if a clean original is to
hand: drop it in as `screenshots/6-result.png` and re-run the tool.

Still worth capturing some time: the camera screen with the oval head guide and a live cue.

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
