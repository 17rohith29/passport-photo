# App Store listing (draft)

Fill these into App Store Connect. Everything here is a draft, not a decision.

## Name (30 characters)

**Free ID Photos** (14)

One caution worth weighing before you commit. Apple's metadata guidelines say an app name must
not include prices or promotional terms, and "free" has drawn rejections under that reading in
the past. Enforcement looks inconsistent, and plenty of shipping apps have it, so treat it as a
real risk rather than a certainty. If you would rather not gamble on it:

- **ID Photos** (9)
- **Passport Photos** (15)

## Subtitle (30 characters)

**Passport and visa, on device** (29)

Alternatives:
- Passport photos that measure up (30)
- Cut to size, on your iPhone (27)

## Promotional text (170 characters)

Turn a photo you already have into a passport or visa photo cut to the exact size your country
asks for. Nothing is uploaded. No account, no subscription.

## Description

Turn a photo you already have into a passport or visa photo that meets the measurements.

Pick your document, choose a photo, and the app measures your face, straightens the picture,
crops it to the exact size that country requires, and tells you what it could and could not
check. Then it shows you how to print it.

Everything happens on your iPhone. The app has no servers and no networking code at all, so
your photo cannot leave the device even by accident. There is no account to make and nothing
to pay for.

WHAT IT DOES

- Measures your head from chin to crown and crops to the exact millimetre the document asks for
- Straightens a tilted photo and replaces the background with the required colour
- Checks the things that can be measured: head size, eye line, head angle, sharpness, even
  lighting, eyes open, mouth closed, and whether the photo is in colour
- Tells you plainly what it cannot check, so a green tick is never mistaken for approval
- Gives you a single photo for an online upload, or a 4 by 6 inch sheet with cut guides
- Walks you through printing it, including how many copies that country wants and where to
  submit them

DOCUMENTS

Australia, Canada, China, India, Russia, Schengen Area, United Kingdom, United States.
Passports and visas.

FOR COUNTRIES THAT DO NOT ACCEPT EDITED PHOTOS

Canada, the United States, the United Kingdom and Australia all rule out a photo that has been
edited with software, and replacing the background counts as editing it. For those four you can
turn on "Keep my own background", and the app will crop and resize only. It will then tell you
honestly whether your own wall is light enough to pass.

HONEST ABOUT WHAT IT CANNOT DO

No app can promise an authority will accept a photo. This one measures what can be measured and
says so. It cannot tell whether you are wearing glasses, how old the photo is, what paper you
print it on, or whether your expression suits the person behind the counter. Every one of those
is listed in the app, per document, so you know what is still yours to get right.

Requirements for each country come from that country's own published guidance, with the source
and the date shown in the app. Where a figure could not be confirmed first-hand, the app says
so rather than pretending.

## Keywords (100 characters, comma separated, no spaces)

passport,visa,photo,id,35x45,2x2,schengen,size,crop,print,biometric,application,document

## Support URL

Needed before submission. A GitHub Pages page or a single page on any domain you own will do.

## Privacy policy URL

Needed before submission. Host docs/store/PRIVACY.md somewhere public.

## App Privacy answers

Data collection: **No, we do not collect data from this app.**

That single answer covers the whole questionnaire, and it was verified rather than assumed:
no URLSession, no Network import, no third-party SDK, no remote package reference anywhere in
the app or its package.

## Age rating

4+. No objectionable content, no user-generated content, no web views, no links out.

## Export compliance

Already declared in the project: ITSAppUsesNonExemptEncryption is false. The app uses no
encryption beyond what iOS does for you.

## Review notes

Suggested text for the reviewer:

  This app works entirely offline. To try it, pick any photo of a face from the library on the
  test device, or use the camera. No account or login is needed. The app has no network code,
  so nothing is uploaded at any point.

  The app never claims a photo will be accepted by any authority. Each document lists the rules
  it cannot check, and shows the official source the requirements were read from.
