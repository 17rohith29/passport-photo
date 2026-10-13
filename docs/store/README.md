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

## Where the raw captures come from

| Source | Screen | Captured |
|---|---|---|
| `1-home.png` | Home | iPhone 17 Pro Max simulator, 12 Oct 2026 |
| `2-picker.png` | Document picker | iPhone 17 Pro Max simulator, 12 Oct 2026 |
| `3-requirements.png` | Requirements, top | iPhone 17 Pro Max simulator, 12 Oct 2026 |
| `3b-cant-check.png` | Requirements, scrolled | iPhone 17 Pro Max simulator, 12 Oct 2026 |
| `4-saved-sheet.png` | Print guidance | **stale**, see below |

To recapture, boot the simulator, build and launch, then flatten the status bar first or the
battery renders green:

```bash
xcrun simctl status_bar <udid> override --time "9:41" --batteryState discharging \
  --batteryLevel 100 --cellularBars 4 --wifiBars 3 --dataNetwork wifi
xcrun simctl io <udid> screenshot docs/store/screenshots/1-home.png
```

A 17 Pro Max capture is exactly 1320 x 2868, which is the size the store wants, so no scaling
is involved anywhere.

## What cannot be captured here, and what is stale because of it

Vision does not run in the Simulator, so every screen past "Choose Photo" is unreachable on this
machine. That covers the result screen and the print guidance.

`4-saved-sheet.png` is therefore **older than the rest of the set** and still shows the India
flow, including "Submit to Passport Seva / VFS Global". Slide 04 is built from it. It is not
wrong, India is a supported document, but it does not match the United States default the other
four slides now show. Recapture it on a device during testing and re-run the tool.

The strongest screenshot the app could have, a finished photo on the result screen with its
measurements, also needs a device. Same for the camera screen with the oval head guide.

## Regenerating

The screenshots are generated, not drawn, by `tools/store-shot.swift`. After a UI change,
recapture with the Simulator and re-run it:

```bash
swift tools/store-shot.swift docs/store/screenshots docs/store/marketing
```

It takes two directories, reads every slide from the `slides` array at the top of the file, and
writes the whole set. Headlines and crops live in that array, not on the command line.

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
