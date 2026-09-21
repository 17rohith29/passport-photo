Paste this into Claude Code after running `claude` in this folder.

---

We're building PassportPhoto, an iOS 18+ app that turns an imported photo into a compliant passport photo, on-device. Start by reading CLAUDE.md, then docs/PLAN.md, docs/ARCHITECTURE.md and docs/LESSONS.md, then specs/ and fixtures/expected.json. reference/python/ holds a working Python pipeline that already produced a good result for fixtures/photos/IMG_0012.HEIC; use it as the behavioral oracle for the Swift port (the mapping table is in ARCHITECTURE.md).

Before writing code, tell me back in a few lines: the milestone order, anything in the docs you think is wrong or risky, and which Vision APIs you plan to use for landmarks, pose and segmentation on iOS 18 (check them against the installed SDK, don't guess).

Then do M0 and M1 and stop for review. Keep swift test green, and fill in the Commands section of CLAUDE.md.
