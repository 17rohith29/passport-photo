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

`marketing/` in numbered order. The first two are what people see in search results, so they
carry the two claims that matter: exact sizing, and honesty about what cannot be checked.

| File | Headline |
|---|---|
| `01-exact-size.png` | Cut to the exact size |
| `02-cant-check.png` | We tell you what we can't check |
| `03-how-to-print.png` | Then we show you how to print |
| `04-countries.png` | Several countries, one tap |
| `05-unedited.png` | Canada won't take an edited photo |

1320 x 2868 is the 6.9 inch size. Apple scales it down for smaller devices, so this one set
covers every iPhone.

## The one that is missing

The result screen, with a real finished photo on it. Vision does not run in the Simulator, so it
can only be captured on a device. It is the most persuasive image the app has and it is worth
getting during testing.

To capture it: run on your iPhone, put it through a photo, and screenshot the result screen.
Send me the PNG and I will composite it the same way. Suggested caption:

> **Your photo, measured** / Head height, eye line and background, all checked

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
