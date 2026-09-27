# WALKTHROUGH-001: alpha walkthroughs

The human walkthroughs UX-001 R10 asked for (WI-024, still open), extended with what UX-003 and UX-004
left for people to decide (REV-051). Nothing in this plan is decided in advance. Each task records what
happened, and ACT-001 decides from the record.

**Data:** made-up only, as for the alpha (REV-034). Use the demo family (`mix findependence.demo`) or the
example household from `project/assurance/accessibility/capture.exs`. Never use a participant's own
finances.

**Who:** people ACT-001 invites as alpha testers. Two co-owners are needed for T9.

**Record for every task:** completed (yes, no, or with help); time from the first action to completion;
errors, and whether they were recovered; what the person said they expected; and any place they
hesitated or asked. Don't prompt unless someone is stuck for more than two minutes, and note it if you do.

## Configurations (UX-004 V1)

Run T1–T7 at least once in each configuration. T9–T12 may run in any configuration.

| Configuration | Browser and tool | Notes |
|---|---|---|
| Keyboard only | Any browser; no mouse or trackpad | Tab, Shift+Tab, Enter, Space, arrow keys |
| Screen reader, Windows | NVDA with Firefox | Tables on phones should keep their column names (UX-001 R10) |
| Screen reader, Mac | VoiceOver with Safari | The pair where stacked tables are known to lose semantics |
| Zoom | Any browser at 200% | No sideways scrolling, nothing clipped |

## Tasks

### From UX-001 (T1–T7)

- **T1** Record "Groceries, $62.40, every week".
- **T2** Let Ben see Groceries.
- **T3** Who can see Rent right now? (answer accuracy and time)
- **T4** Make Rent shared with Ben, then propose it back to just you, then withdraw.
- **T5** Link Groceries to "Family" and say how much went toward Family.
- **T6** Respond to Ben's invitation.
- **T7** Prepare to leave and keep a copy of your information.

### Added by UX-004

- **T8 · The weekly check-in (H1).** As Dad in the demo, bring every account and debt up to date with
  new made-up balances. Record the total time, the number of pages visited, and any errors. This
  decides UX-002 R3 (all balances on one page); nothing is built for it before this runs.
- **T9 · Joint checking (P2).** Two co-owners, separately, as Dad and then as Mom: "Will joint checking
  go below zero before October 6, and by how much? Why might your answer differ from Mom's (or
  Dad's)?" Record whether each notices "Your part after", and whether they can say why the views differ.
- **T10 · A slow form (P5, CP-016).** With a screen reader, fill in the retirement assumptions using
  made-up figures from a printed sheet. Record the time taken, and whether the 15-minute lock
  interrupted. This is evidence for the security review's decision on CP-016.
- **T11 · First use (H2).** In an empty household: "Get the app to show what's coming up this week."
  Record the first-attempt path, and whether the person adds an account's balance without being told.
- **T12 · Finding features (X4).** From home, with no hint: "Open your retirement projection", then
  "Start a plan for losing a job". Record the time to each and where the person looked first. If
  people don't find them from the link row in Coming up, that is the evidence for trying header links
  (UX-004 X4); nothing is built before it.

### Observations for UX-003's experiments

While running the tasks above, note:

- **X1 (touch size):** any missed or mistaken tap on Agree, Withdraw, Remove, Lock, or other small buttons, on a phone.
- **X2 (return to context):** after acting in a card far down an item page, whether the person looks for the result at the top, or scrolls back to the card.
- **X3 (one solid button per card):** on a plan's "Add a step" card, which button the person reaches for first.

## Browser pass (UX-004 V2)

Before any pilot, one person with Safari (macOS) and Firefox (Windows or Linux) opens add item (with a
mistyped amount), a plan, the unlock page, and a debt's page, at full width and at phone width, and
notes anything that looks different from Chromium. In particular: whether select boxes still show their
arrow on a white background (UX-003 C4), and whether the focus outline shows on date fields.

## After the walkthroughs

Record the results as a run (`project/assurance/runs/`), with any Defeaters they raise. ACT-001 decides
UX-002 R3, UX-004 X4, and UX-003 X1–X3 from them. The security review receives T10's record with CP-016.
