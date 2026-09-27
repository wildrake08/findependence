# ROADMAP-ALPHA: from v0.1.0-alpha to v0.5.0-alpha

**Status:** accepted by ACT-001 (REV-038), with the recommended answers to all four questions in §6:
the 16-year-old is a full member in the alpha, members living away are recorded as DEF-030, Grandma
is not a member, and agreed shares (CAP-008) are deferred. Every version remains alpha: internal testing with made-up data only (REV-034).

## 1. Who the alpha is built around

A made-up family, used for design, the demo household, and testing. Any resemblance in the details
is deliberate, but every figure in the demo is invented.

| Person | Situation |
|---|---|
| **Dad** | Main paycheck. Out of work twice in the last three years. Wants to start a side business and invest in "passive income" to build resilience and perhaps replace his paycheck. |
| **Mom** | Paycheck. With Dad, pays all household bills. |
| **Kid, 20** | In college. Grandma pays all college costs. Part-time job; own spending money. |
| **Kid, 18** | In college. Same as above. |
| **Kid, 16** | In high school. Possibly a first job. College is two years away. |
| **Grandma** | Lives in her own household. Pays the college kids' tuition directly. **Not a member** (see §6). |

What the family is dealing with:

- It often **runs out of money between paychecks**.
- It carries **several debts**: credit cards and HELOCs (usually variable-rate).
- It **isn't sure it's saving enough to retire**.
- Its **income has been unstable** (two job losses).
- Two members **live away at college** most of the year.
- College depends entirely on **one person outside the household**.
- The parents have **split costs with the kids** in the past (a gym), but pay household bills in full.

## 2. Principles every version keeps

1. **Facts, never advice.** The app shows what the family's own records imply ("checking would go
   below zero on the 23rd", "interest this month: about $84"). It never recommends a payoff order, an
   investment, a product, or says whether something is enough (PRI-001). Investment and tax advice are
   also regulated.
2. **The family's own goals.** Targets (an emergency fund, a retirement income, a tax set-aside rate)
   are set by the family; the app shows progress toward *their* target, with no default target of its
   own.
3. **Privacy by default.** Every new kind of record (a balance, a debt, a plan) is private to its
   owner until shared, like items today (PRI-002, CAP-001). A card in one spouse's name stays theirs.
4. **Nothing leaves the device.** No bank connections, no network (REQ-124). Balances are typed in.
5. **Checked information only.** Anything that presents rules or resources (benefits, taxes, scams,
   credit counseling, financial aid) waits for professional review (§5).
6. **Bounded burden** (OUT-009). No daily upkeep. A monthly five-minute check of balances is enough
   to keep everything useful.

## 3. The seamless UX contract (applies to every build)

ACT-001 requires that every interface build sustains a seamless experience. Each version is released
only when all of these hold, checked and recorded in its WorkItem:

**Structure**

- **Home stays short and in this order:** what's waiting for you, **coming up** (v0.2), your items and
  values, the totals, leaving. New features live on their own pages, one click from home, never as
  more forms on home. Home at 50 items stays within its WI-027 size on phones (7,012 px) plus at most
  one screen for "coming up".
- **One page per thing.** Every new kind of record (balance, debt, plan) gets a page like an item page:
  its facts first, then what you can do, then its history. Actions return to where they were taken,
  with a message that says what actually happened (UX-001 R1, R6).
- **Plans never mix with what's real.** Anything hypothetical is labelled as a plan everywhere it
  appears and is never counted in real totals.

**Words and numbers**

- **One word per concept.** New terms join the glossary and its test before they ship. Expected
  additions: *balance*, *debt*, *interest*, *plan*, *coming up*, *set aside*, *goal*.
- **Every number says what it is:** amounts show their schedule ("a month", "twice a year"),
  projections show their assumptions next to the result, and dates are written out ("Friday, March
  13"), never bare.
- **No judgment words** in computed results: no good, bad, risk, healthy, on track, over budget (a test
  scans every page, as the glossary test does).

**Forms**

- **No JavaScript** (the CSP forbids it). Every form works with plain HTML; nothing is chosen for the
  member; errors appear at the field with what was typed kept (UX-001 R2).
- **New fields are optional unless the feature can't work without them,** so existing items keep
  working and adding an item doesn't get harder. For example, a due date is optional; items without
  one simply don't appear in "coming up".

**Quality gates, every version**

- Accessibility: axe-core clean at 1200 and 390 px on every page; Chromium's accessibility tree keeps
  table semantics on phones; a scripted Tab walk reaches every control in order.
- Phone layout at 390 px: no table overflows its box; nothing clipped.
- Screenshots of every new page with the family demo, reviewed against UX-001's seamless target, and
  the screens gallery updated.
- Performance: every page under 50 ms of server time at 200 items.
- All earlier pages unchanged unless the version says otherwise (a before/after comparison, as in
  WI-030).

## 4. Versions

Each version: Capabilities accepted by ACT-001, Functions/Mechanisms/Requirements specified under
delegation (CP-002), a WorkItem per Capability, tests and deliberate-break checks, the §3 gates, a
clean reproduction, and a tag after ACT-001 approves the merge.

### v0.2.0-alpha: balances, debts, and the next 60 days

*For: running out between paychecks; seeing all debts in one place.*

| Capability | What a member gets | Outcomes |
|---|---|---|
| **CAP-010 Balances and debts** | Record accounts (checking, savings) and debts (cards, HELOCs, loans) with a balance, and for debts an interest rate and minimum payment. Private by default, shareable like items. Each has its own page. | OUT-001, OUT-006 |
| **CAP-011 Dated cash flow** | Items can say when they next happen (optional). A **coming up** section on home: the next 14 days of bills and paychecks with the running checking balance. A **next 60 days** page, day by day, marking any day the balance would go below zero. **Set-asides for lumpy bills**: "setting aside about $X a month covers these" for items that come a few times a year. | OUT-001, OUT-006 |

Also in v0.2: **`mix findependence.demo`**, which creates the family in §1 with made-up figures, so
testers start from a realistic household.

Requirement changes needing ACT-001: items gain an optional next date (changes REQ-129).

### v0.3.0-alpha: looking ahead, and plans

*For: job losses, debt growth, the side business, Grandma's support.*

| Capability | What a member gets | Outcomes |
|---|---|---|
| **CAP-007 Projection and plans** (revised from OBA-003) | A **12-month projection** including interest on debts. **Plans** kept apart from what's real: switch off an income or cost from a chosen month (a job loss, Grandma's support stopping), or add planned costs and income (a side business, an investment), shown side by side with "as things are". Borrowing to fund a plan shows its interest in the plan's path. **What depends on the job**: items marked as depending on a job switch off with it, and replacement costs (e.g. marketplace health premiums) can be added to the plan. **Debt "what if"**: an extra payment's effect on months to clear and interest; a rate rise's effect on a HELOC payment. | OUT-001, OUT-006, OUT-007 |
| **CAP-013 Goals the family sets** | An emergency fund goal in the family's own terms (e.g. "3 months of money out"), with **how long savings would last** at current money out, and progress toward the goal. A **tax set-aside** at a rate the family chooses for business income. | OUT-006 |
| **CAP-005 extension: shared plans** | A plan that affects everyone (the side business) can be proposed to the adults and needs their agreement, through the existing request-and-agree mechanism. | OUT-004 |

### v0.4.0-alpha: retirement

*For: not knowing whether they're saving enough.*

| Capability | What a member gets | Outcomes |
|---|---|---|
| **CAP-012 Retirement projection** | Retirement accounts (401(k), IRA) with balances and contributions. A long-range projection to a retirement age the family chooses, under assumptions they set and can see (return, contributions, a Social Security estimate they enter from their own statement), compared with **their own** target income. Changing an assumption shows how sensitive the result is. No investment or product suggestions. | OUT-007, OUT-001 |

### v0.5.0-alpha: taking your record with you

| Capability | What a member gets | Outcomes |
|---|---|---|
| **CAP-009 Portable record** | Bring your own export into a new household file, as items and values you own with your links, for a kid moving out, or anyone leaving. The file is untrusted input and checked strictly. | OUT-007, OUT-008 |

After v0.5, the alpha covers OUT-001, OUT-002, OUT-004, OUT-005, OUT-006 (in part), and OUT-007.

## 5. What this family needs that the app cannot yet provide safely

| Need | Why not yet | Unblocked by |
|---|---|---|
| Help when income stops: Washington unemployment insurance, marketplace health coverage | Presenting benefit rules needs checked information (OUT-003) | Professional check of the Washington notes (GATE-016, after the alpha) |
| Credit counseling resources; scam awareness for "passive income" offers | Presenting resources and warnings needs checked sources (OUT-006 exploitation) | Same review |
| College financial aid and FAFSA timing for the 16-year-old | Entitlement information; involves sharing parents' details with a child | Same review, plus a decision on the minor's standing (§7) |
| "If something happens to me": a summary someone else could use | Access by another person changes key handling (OUT-008) | Independent security review |
| Using it from college | One device only (CP-006 B) | An architecture decision after the security review (§6, question 2) |
| Agreed shares of joint items (CAP-008) | Parents pay bills in full; past splits can be separate items | Reconsider if testers need it |
| Low-effort upkeep in bulk (CAP-006) | Deferred by ACT-001 pending evidence (REV-005) | STUDY-001 Q5 |

## 6. Open questions, with recommendations

1. **The 16-year-old.** Recommended for the alpha: **(a) a full member** with the same privacy as
   everyone (no real minor is involved; made-up data). Alternatives: (b) not a member, parents record
   items about them, as STUDY-001 requires; (c) a member whose items the parents can see (conflicts
   with PRI-002). The stance for real minors is decided with the ethics body before any pilot.
2. **Members living away (college).** Recommended: **record as a defeater** against CP-006 B now; decide
   between per-member devices with home sync (CP-006 A) and remote access after the security review.
3. **Grandma.** Recommended: **not a member**; her support recorded both ways (money in and tuition
   out, linked to "The kids' education"), so the real cost and the dependence stay visible. A later
   "paid by someone outside the household" marker is possible if testers find this awkward.
4. **Agreed shares (CAP-008).** Recommended: **defer** (§5).

## 7. How the roadmap changes

New needs become proposed changes to this roadmap, not side-builds. Accepting the roadmap accepts
CAP-007 (revised), CAP-010, CAP-011, CAP-012, CAP-013, and the CAP-005 extension as the alpha's
Capabilities, and CAP-009 as already proposed; each version still needs ACT-001's approval to merge and
tag, and any change to an accepted Requirement is shown to ACT-001 with the version that needs it.
