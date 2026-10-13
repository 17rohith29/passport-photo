# App Store listing (draft)

Fill these into App Store Connect. Everything here is a draft, not a decision.

## Name (30 characters)

**Exact ID Photo** (14)

Chosen over the generic options because the category is saturated. Every obvious combination is
already on the store: "Passport Photo - ID Photo", "ID Photo - Passport Photo App", "ID
Photo-Passport Photo maker", "Passport Photo & ID Photo", "ID Photo: Passport Photo Maker" and
more. A fiftieth near-identical name would be invisible in search, and the name is not where
discovery comes from anyway: that is the keyword field and the subtitle.

Dropping "Free" also removes a rejection risk. Apple's metadata guidelines say an app name must
not include prices or promotional terms, and "free" has drawn rejections under that reading.

**Check availability in App Store Connect before anything else.** Search results only show what
ranks, not what is reserved, so this cannot be confirmed from outside. Reserving is free and
instant. Have a second choice ready:

- **Cut to Size** (11)
- **Passport Rules** (14)

## Subtitle (30 characters)

**Passport and visa, on device** (29)

The first draft, "Passport and visa, sized exactly", was 33 characters against a 30 limit. Of
the replacements that fit, this is the only one carrying both "passport" and "visa", which the
subtitle is indexed on, and it states the thing most of this category cannot claim. The others
stay available, and the subtitle can be changed without a new build:
- **Cut to the exact size** (21)
- **Passport photos that measure up** (30), but it drops the word visa

## Promotional text (170 characters)

Turn a photo you already have into a passport or visa photo cut to the exact size your country
asks for. Nothing is uploaded. No account, no subscription.

(Avoid naming a country count here. It goes stale the moment one is added, and promotional text
is one of the few fields you can change without submitting a new build.)

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

Passports and visas for several countries, with more added over time. Today: Australia, Canada,
China, India, Japan, Russia, the Schengen Area, the United Kingdom and the United States.

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

35x45,2x2,schengen,biometric,crop,size,print,offline,usa,uk,canada,india,japan,china,australia

(94 of 100)

The earlier draft opened with passport,visa,photo,id. Apple indexes the name and subtitle
together with this field, so all four were already covered by "Exact ID Photo" and "Passport
and visa, on device" and were spending 23 characters to say nothing. That space now holds the
country names, which is what turns a search like "canada passport photo" into a match. Russia
is the one supported country left out, on volume. Add it if a country is ever dropped.

## Support URL

https://17rohith29.github.io/passport-photo/

## Privacy policy URL

https://17rohith29.github.io/passport-photo/privacy.html

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

## Screenshots

`docs/store/marketing/` holds five at 1320x2868, the 6.9 inch size Apple requires. Upload in
the numbered order: the first two are what people see in search results, so they carry the two
claims that matter most, namely the exact sizing and the honesty about what cannot be checked.

They are generated, not hand-made, by `tools/store-shot.swift`. To change a caption or reshoot
after a UI change, recapture with the simulator and re-run that tool. The palette comes from the
app icon: navy #2E3866 to #141936, amber #F7BC4C, with the icon's crop marks framing the device.

`docs/store/screenshots/` holds the raw captures they are built from.

Missing, and only reachable on a real device because Vision does not run in the simulator: the
result screen with a finished photo on it. That is the most persuasive screenshot the app has,
and it is worth capturing during device testing. A photo of a stranger is fine for the store as
long as you have their permission, or use your own.
