# CTX-001: brief for the professional legal check

**For:** a Washington-licensed attorney or privacy professional (GATE-016 `3_professional_check`).
**From:** the Findependence project (decision holder ACT-001; the AI agent ACT-002 drafted this brief and the notes
it asks you to check).
**Why:** [CTX-001-washington-notes.md](CTX-001-washington-notes.md) lists rules an AI agent thought might apply,
from general knowledge that may be outdated or wrong. **None of it is verified, and it is not legal advice.** No
household may take part in the study until a professional has checked it.

## 1. What the project is

A research prototype of a household finance tool. Adults record their own money in and out, accounts and debts,
and what they value; each person's information is encrypted separately and shared only by their choice. It gives
**no advice**, **moves no money**, connects to **no bank**, and holds **no card data**. It shows facts and
projections the member configures (a cash-flow forecast, a twelve-month projection, a retirement projection under
the member's own assumptions), never suggestions.

It exists in two forms:

- **Local-first** (the one the study uses): runs on one household computer; everything stays on that computer;
  nothing is sent anywhere. The project holds no participant data.
- **Hosted** (built, not in service, offered to no one): a web service in which the operator's server can read a
  member's information while they are signed in, as members are told before signing up.

The study (STUDY-001): 3 to 5 households in or near Sumner, Washington, 4 weeks each, adults only, private
interviews; the researcher keeps notes in participants' own words and never records amounts, account details,
passwords, health details, or copies of the tool. Participants may receive an incentive.

## 2. What we are asking

For each item in the notes: **does it apply, is our description right, and is what the design does enough?** Most
of all:

| # | Question |
|---|---|
| Q1 | **Health data (W2).** Does Washington's My Health My Data Act apply to the study's interview notes, or to the tool, given that household finances can reveal health (therapy, pharmacy, medical bills)? |
| Q2 | **Promises to participants (W4, F1).** Are the information sheet and consent form true and complete under the Consumer Protection Act and FTC Act section 5? (We have found one gap ourselves: see the ethics brief, section 6, and DEF-081.) |
| Q3 | **Advice (W5).** Could showing a member their own retirement or cash-flow projection, under assumptions they choose, count as investment or financial advice under the Washington Securities Act or federal law? |
| Q4 | **A comprehensive Washington privacy law (W6).** Has one been enacted, and does it apply? |
| Q5 | **Incentives (F5).** Any reporting or tax thresholds, and anything about paying each adult individually? |
| Q6 | **Recording (W1).** Is all-party consent, captured at the start of each recording, enough? |
| Q7 | **Reporting duties.** Does anything oblige the researcher to report what a participant discloses (for example abuse)? The consent form must say so if it does. |
| Q8 | **The hosted form, before it is offered to anyone** (CTX-001 jurisdiction: United States, starting with Washington): does the Gramm-Leach-Bliley Act or the FTC Safeguards Rule apply to a service that stores members' encrypted financial records and whose operator can read them while they are signed in? What else applies to it (breach notification, health data, state privacy laws)? Is its disclosure (REQ-180) enough? |

## 3. Documents

| Document | What it is |
|---|---|
| [CTX-001-washington-notes.md](CTX-001-washington-notes.md) | The notes to check (W1..W6, F1..F5, S1), with the agent's own confidence for each |
| [STUDY-001-household-observation.md](STUDY-001-household-observation.md) | The study protocol |
| [study-001-materials/](study-001-materials/) | Information sheet, consent form, screening script, safety resources, researcher checklist (drafts) |
| [STUDY-001-ethics-review-brief.md](STUDY-001-ethics-review-brief.md) | The ethics brief, including the known risks |
| [../../../hosted/DEPLOY.md](../../../hosted/DEPLOY.md) and [../design/OPS-001-hosted-operating-controls.md](../design/OPS-001-hosted-operating-controls.md) | For Q8: what a hosted deployment does and must satisfy |

## 4. What we would like back

- For each item and question: applies or not, any correction, and anything the design or materials must change.
- Anything we haven't listed.
- Whether the study may proceed on the legal side, and under what conditions.

Your conclusions will be recorded as the check GATE-016 requires, in your words.
