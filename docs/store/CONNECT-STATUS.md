# App Store Connect: what is set, and what is not

Apple ID 6821543056. Verified by reloading each page after saving, not by
trusting the save.

## Set and confirmed

| Section | Value |
|---|---|
| Name | Exact ID Photo: Passport Size (29/30) |
| Subtitle | Visa sizes, nothing uploaded (28/30) |
| Promotional text | 158/170 |
| Description | 2,567/4,000 |
| Keywords | 95/100 |
| Support URL | https://17rohith29.github.io/passport-photo/ |
| Marketing URL | https://github.com/17rohith29/passport-photo |
| Privacy policy URL | https://17rohith29.github.io/passport-photo/privacy.html |
| Version / Copyright | 1.0 / 2026 Rohith Prabakar |
| Primary category | Photo & Video |
| Secondary category | Utilities |
| Age rating | 4+, 172 countries, no override, not Made for Kids |
| Content rights | No third-party content |
| App privacy | Data Not Collected (saved, NOT published) |
| Price | $0.00, all currencies |
| Availability | 175 countries |
| Review notes | 404 chars |
| Review contact | name, phone, email |
| Sign-in required | unchecked |

Apple defaults "Sign-in required" to CHECKED. Left as-is it demands a test
username and password, and the whole App Review Information block then fails
to save with no visible error. That is how the first save was lost.

## Not set, and why

- **Screenshots.** Five are ready at 1320x2868 in docs/store/marketing/.
  A browser cannot populate a file input from a path, so these have to be
  dragged in by hand.
- **Build.** Nothing uploaded. Archive and upload from Xcode.
- **App privacy publish.** The answers are saved; the Publish button has not
  been pressed.

## Category choice

Pulled the top results for "passport photo" from the iTunes Search API:
7 of 10 use Photo & Video as primary, and Utilities is the most common
secondary. That is where this now sits.

## Keyword reasoning

Apple indexes name, subtitle and keywords together, so a word in the name
is wasted in the keyword field. "size" moved into the name, so it came out
of keywords. Nothing in the keyword string repeats the name or subtitle.
