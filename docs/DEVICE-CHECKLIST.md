# On-device checklist

Vision does not run in the iOS Simulator, so everything past "import a photo" has only ever been
reasoned about, never executed. This is the list of things a device run settles and nothing else
can. Roughly ten minutes.

Build: open `PassportPhoto.xcodeproj`, pick your iPhone, Run. Signing is already working
(Apple Development, Team Provisioning Profile).

## 1. The import path, does it finish?

- [ ] Home → **Choose Photo** → pick a normal portrait. It should tick through Reading →
      Checking → Separating → Cropping → Verifying and land on a result.
- [ ] Time it. Release should be ~1.5-2 s for a 24 MP photo. If it takes 30 s+ you are on a
      Debug build; that is expected and not a bug.
- [ ] Try a photo you know is bad (eyes closed, or taken against a dark wall). You should get the
      rejection screen, naming what is wrong in plain words, no decimals like "0.171 / 0.180".

## 2. The result and save path, never run anywhere

- [ ] The photo should look right: square-on, correct background, no halo around the hair.
- [ ] Toggle **Measurements**. Crown/chin lines should sit on the actual crown and chin.
- [ ] Switch to **Print sheet**. The Measurements toggle should go grey (it does nothing there).
- [ ] **Save** → **Save to Photos**. Grant access. The **Saved** screen should appear by itself.
- [ ] On the Saved screen, tap **Done**. *Known unknown:* this collapses a sheet and a
      full-screen cover in one transaction. If the Saved sheet lingers over Home, or Home stays
      covered, that is the bug to report.
- [ ] Save again and tap **Save to Photos** twice quickly. You should get exactly ONE photo in
      your library, not two.
- [ ] Check the saved file in Photos: it should be exactly the spec's pixel size.

## 3. The camera, the largest untested surface

- [ ] Home → **Take a Photo**. Grant camera access.
- [ ] *Known unknown:* does the oval head guide line up with what the cues are asking for? If you
      fill the oval and it still says "Come closer", the guide is sized off the wrong rect.
- [ ] The **Auto** and **Voice** buttons must both be readable. Voice should start OFF.
- [ ] Turn Voice on. It should speak cues, and stop when you leave the screen.
- [ ] **Move the camera low** (chest height). It should say **"Raise the camera"**. If it says
      "Lower", the fix in this round was wrong, tell me immediately, that cue was inverted.
- [ ] Stand in front of a dark wall. It should say **"Find a lighter wall behind you"**.
- [ ] Stand in side light. It should say **"Turn towards the light"**.
- [ ] Let auto-capture fire. Then try the shutter manually.
- [ ] **Cancel** mid-preview. The camera must stop, no green dot lingering in the status bar.
- [ ] Flip to the front camera and back. The preview must not freeze or say "No camera".

## 4. Interruptions, fixed this round, never tested

- [ ] With the camera open, swipe to the home screen, wait 3 s, come back. The preview must come
      back live. Before this round it stayed frozen with a live shutter over a dead session,
      which could take the app down.
- [ ] Same with Control Center pulled down, and with a phone call if you can arrange one.
- [ ] Take a photo, then immediately background the app while it is processing.

## 5. Cancel and re-enter

- [ ] Import a photo, hit **Cancel** while it is working, then immediately import another.
      The second one must run its own progress from the start, not jump to five green ticks and
      sit there.

## 6. Accessibility, if you have a minute

- [ ] Settings → Accessibility → Display → Larger Text, near maximum. Walk Home → Requirements →
      picker. Nothing should clip or push the primary button off screen.
- [ ] VoiceOver on the capture screen: cues should be announced as they change.

## What to send back

Screenshots of anything wrong, plus which step number. If the app crashes, the crash report from
Settings → Privacy & Security → Analytics & Improvements → Analytics Data (search PassportPhoto).
