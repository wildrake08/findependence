# Visual direction (CP-017 option C, REV-075)

`DIR-001-premium.css` is the stylesheet proposed for ACT-001's review on 2026-09-28: the app's current
`@css` (web.ex) with new tokens and component styling, a dark palette under `prefers-color-scheme`, and the
phone and forced-colours blocks carried over unchanged. It was applied to pages rendered by
`accessibility/capture.exs` and screenshotted in Chromium at 1200 and 390 px, in light and dark, with Inter
standing in for the Mac and Windows system fonts. Review page: https://claude.ai/artifact/Fu3dNoqwJaaym897yFAZM3 (private).

It is a proposal, not in the app. The implementation WorkItem must pass the checks listed on the review page
(app tests, check, trace, e2e, axe in both themes, focus contrast, geometry, forced colours) before it replaces
`@css`.
