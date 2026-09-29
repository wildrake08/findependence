# Visual direction (CP-017 option C, REV-075)

`DIR-001-premium.css` is the stylesheet proposed for ACT-001's review on 2026-09-28: the app's current
`@css` (web.ex) with new tokens and component styling, a dark palette under `prefers-color-scheme`, and the
phone and forced-colours blocks carried over unchanged. It was applied to pages rendered by
`accessibility/capture.exs` and screenshotted in Chromium at 1200 and 390 px, in light and dark, with Inter
standing in for the Mac and Windows system fonts. Review page: https://claude.ai/artifact/Fu3dNoqwJaaym897yFAZM3 (private).

It is a proposal, not in the app. The implementation WorkItem must pass the checks listed on the review page
(app tests, check, trace, e2e, axe in both themes, focus contrast, geometry, forced colours) before it replaces
`@css`.

# Reference architecture (CP-019, REV-078)

`ARCH-001-reference-architecture.md` is ACT-001's reference architecture for Findependence as a hosted
service (Phoenix, LiveView, Petal Components, PostgreSQL), stored unedited. ACT-001 adopted it as the
hosted edition's target; it does not govern the local-first interface, which DIR-001 and WI-062 style. How it
maps onto the project, and what it leaves open, is in `project/change/CP-019.yaml` and DEF-056.

# Target structure (ARCH-002, REV-081)

`ARCH-002-target-structure.md` is ACT-001's reference structure for the target application, stored unedited:
every client (LiveView, the JSON API for iOS and Android, Alexa, provider webhooks) enters through one set of
public contexts; PostgreSQL is canonical; Oban carries durable consequences; PubSub refreshes after commit.
ARCH-001 stays the normative text. What ARCH-002 leaves open is listed in REV-081.

# Platform reference architecture (ARCH-003, REV-082)

`ARCH-003-platform-reference.md` is ACT-001's domain-neutral platform reference architecture, stored unedited,
and the final target (REV-082). Findependence's meaning enters through a domain profile (ARCH-003 37). How the
project moves toward it, and how ARCH-001 and ARCH-002 relate to it, is proposed in `project/change/CP-020.yaml`.
