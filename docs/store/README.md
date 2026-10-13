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
| `01-what-it-does.png` | Turn a photo into a passport photo | What the app is, in one line |
| `02-measured.png` | Measured, not guessed | It is measurement, not a crop tool |
| `03-honest.png` | Honest about what it cannot check | The thing no competitor does |
| `04-print.png` | Exactly how to print it | The part people actually get wrong |
| `05-countries.png` | Each country's own published rules | Free, no account, nothing uploaded |

All five show **one part of a screen, enlarged**, except the last. A full iPhone screen is
unreadable at the size these are browsed at, and on the home screen the lower half is empty.

Every headline stands on its own. Apple shows one or two of these in search results, so a
caption that only parses after reading the previous slide is one most people never read. That
is why slide 1 names the function rather than opening a story, and why slides 3 and 4 no longer
begin with "And" and "Then".

When changing a `.detail` crop, re-render and look at the result. The crop is in source pixels
and does not know where a row ends, so it will happily cut a sentence in half or catch the
scroll indicator.

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
