# Accessibility checks (UX-001 R10, WI-024)

Automated checks only. They do **not** replace the keyboard-only and screen-reader walkthroughs
of tasks T1–T7, which need a person and are still open.

## Tools

- `capture.exs` renders every page type from a seeded demo household into a directory:
  `cd app && ITEM_PAGES=1 mix run ../project/assurance/accessibility/capture.exs <dir>` (the directory must exist).
- `axe.sh <dir> <out>` (or `KIND=incomplete axe.sh …` for "needs review") runs axe-core on each page at 1200 px (window) and 390 px (inside a 390 px
  frame, because headless Chromium windows are at least 500 px wide). It expects `axe.min.js`
  next to it. It is not committed; fetch the pinned copy and check its hash:
  `curl -sSfL -o axe.min.js https://cdn.jsdelivr.net/npm/axe-core@4.10.2/axe.min.js`, then
  sha256 `b511cd9dec01c76f4b2ad1723b66b6db37d4c2eb4ed199076e1829d9ee7b75e3`.
  The runner was checked against a deliberately faulty page, where it reported the faults.
- `axtree.py <page> <width>` reads Chromium's accessibility tree through the DevTools protocol
  and counts table roles, to see whether the phone layout keeps table semantics.
- `tabwalk.py <page> <width>` presses Tab through the page and reports how many controls were
  reached, whether in DOM order, any positive tabindex, and any control without a visible focus outline.

All need `/usr/bin/chromium` and Python 3 (standard library only).

## Results, 2026-09-26 (16 pages × 2 widths)

| Check | Before WI-024 | After |
|---|---|---|
| axe-core 4.10.2 violations (any impact) | 0 | 0 |
| axe-core "needs review" | 0 | 0 |
| Chromium tree, home at 390 px: column headers / row groups | 3 / 1 (1200 px: 10 / 3) | 10 / 5 (same as 1200 px) |
| Cell name at 390 px | "Item Car loan" (label read into the cell) | "Car loan" |
| Tab walk | — | every control reached in DOM order, visible focus on each, no positive tabindex; the unselected radio of the Money in/out pair is reached with arrow keys, as native radio groups work |

axe checks the DOM, not the browser's accessibility tree, so it can't see the table problem;
the tree reading is what showed it. It is one engine (Chromium). Safari with VoiceOver and
Firefox with NVDA are the combinations where display:block tables are known to lose semantics;
the explicit roles address that, but only the human walkthrough can confirm it.
