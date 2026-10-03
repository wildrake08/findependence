# STUDY-001: brief for the independent ethics review

**For:** the ethics review body asked to review STUDY-001 before any household takes part (GATE-016
`2_ethics_review`).
**From:** the Findependence project (decision holder ACT-001; the AI agent ACT-002 drafted this brief and the study
materials).
**Status:** the protocol is approved by the project owner (REV-007). Nothing has started: no household has been
approached, and none may be until this review, an independent security review, and a professional legal check
are complete.

## 1. The study in brief

Findependence is a research prototype of a household finance tool. Each adult in a household records their own
money in and out, accounts and debts, and what they value, in their own words. Each person's information is
encrypted separately and shared with other members only if they choose. Shared decisions need every owner's
agreement, and anyone can take their own record and leave. It gives no advice and moves no money.

STUDY-001 is a small, exploratory, qualitative study: **3 to 5 households in or near Sumner, Washington, for 4
weeks each**, using the tool on one household computer with their real information. Each adult has a private
onboarding, a private check-in in week 2, and a private exit interview in week 4, with an optional joint session
only if every adult wants one. The study asks six questions (protocol section 2): whether members understand and
feel in control of who sees their information, whether they understand they could leave, whether seeing activity
against their values helps without feeling judged, whether the consent rules get in the way of doing things
together, how much time it costs, and whether members want to correct items.

It exists to find where the design's assumptions are wrong. Contradicting findings are expected.

## 2. What we are asking

1. **Is the study ethically sound as designed**, and under what conditions may it proceed?
2. **Are the participant materials adequate** (section 3)? Please mark them up.
3. **The decisions the protocol leaves to you** (section 4).
4. **Coerced consent** (section 5): is the screening, with the 72-hour cooling-off now built, enough, and is 72 hours the right length?
5. **Any risk we haven't named.**

## 3. Documents

| Document | What it is |
|---|---|
| [STUDY-001-household-observation.md](STUDY-001-household-observation.md) | The protocol: why, questions, design, who takes part, what is and isn't collected, consent, conduct, how findings are used |
| [study-001-materials/1-information-sheet.md](study-001-materials/1-information-sheet.md) | Information sheet, in plain language |
| [study-001-materials/2-consent-form.md](study-001-materials/2-consent-form.md) | Consent form, signed by each adult privately |
| [study-001-materials/3-screening-script.md](study-001-materials/3-screening-script.md) | The private safety screening |
| [study-001-materials/4-safety-resources.md](study-001-materials/4-safety-resources.md) | Safety resources given to every participant |
| [study-001-materials/5-researcher-checklist.md](study-001-materials/5-researcher-checklist.md) | The researcher's checklist |
| [CTX-001-washington-notes.md](CTX-001-washington-notes.md) | Unverified notes on Washington and federal rules (under separate professional review) |
| [../security-review/README.md](../security-review/README.md) | The security review brief, with the known weaknesses in full |

All materials are drafts written by an AI agent. None has been used with anyone.

## 4. Decisions the protocol leaves to you

| Where | Decision |
|---|---|
| Protocol section 4 | What happens if an adult joins a participating household during the study (the tool can't add a member after setup): screen and set up again, or the household leaves the study |
| Consent form | When the researcher may have to share something a participant says (for example immediate danger), and any reporting duties that apply |
| Safety resources | The Washington State and Pierce County entries are left blank on purpose; a wrong number could cause harm. They must be filled from a current official source and checked by calling them |
| Protocol section 6 | Incentives: amount, and paying each adult individually |

## 5. Known risks, and how the design handles them

The central concern of the tool is that **a member's information stays theirs even from other members of their
household**, including where one partner controls another financially. That is also the study's main risk.

| Risk | What the design and protocol do | What remains |
|---|---|---|
| **A participant is pressured into sharing, giving away, or deleting** (DEF-016) | Households where any adult privately reports fear of, or control by, another member are not enrolled; every participant receives safety resources privately; consent is individual and private | The tool can't detect coercion. Since v0.8.4, sharing, giving away, and deleting wait 72 hours once every owner has agreed, and anyone whose agreement it rests on can cancel it alone, privately (CP-030, REV-115). On one shared computer the person applying pressure may be present for the whole wait. **We ask whether this, with the screening, is enough, and whether 72 hours is right.** |
| **Someone who can edit the household file changes who can see what** (DEF-028) | Content stays encrypted and signed; a key is never given to someone written into the file; changed records are reported on screen | Since v0.8.5 another member's agreement can't be forged: each agreement is signed with its member's own key. A member with access to the computer can still remove someone from an item or restore an older copy of the file. A fix is designed (DESIGN-002) and waits for the security review. **The current consent form does not say this** (DEF-081): see section 6. |
| **Others on the device can see the structure** (ASM-020) | Stated in the consent form: someone with the device can see who owns each item and who can see it, but not what it is | None beyond the statement |
| **Security not independently reviewed** (DEF-026) | The study cannot start until it is | — |
| **Loss of data** | Stated: no backup; forgotten passphrases can't be recovered; members can save their own copy | — |
| **Health details in notes** | Notes never record health details; participants describe categories | Applicability of Washington's health-data law is under professional review |
| **Recording** | Notes by default; audio only with every present person's consent each time (Washington all-party consent) | — |
| **Children** | Adults only; adults may record items that relate to children | — |
| **Advice** | Neither the tool nor the researcher gives advice of any kind | Whether projections could count as advice is under professional review |
| **The researcher's role** | The researcher is the project owner or someone they designate | **The project owner built the tool and decides on its future.** We ask whether an independent researcher should run the sessions, or what safeguards you require |

## 6. A correction to the consent form we ask you to consider

The consent form says someone with access to the device "could see **who** owns each item or value and who else
can see it, but not **what** it is." That is true as far as it goes, but incomplete: someone who can edit the
household file can also remove someone from an item, or put back an older copy of the file, undoing recent
changes (DEF-028). (Forging another member's agreement is no longer possible since v0.8.5.) Promises to participants must be true and complete
(Washington Consumer Protection Act and FTC Act notes, W4 and F1). We propose adding, until DESIGN-002 is built:

> ☐ I understand that someone who can change files on this computer could change who can see what, or undo
> recent changes, and that the tool may not always be able to tell. It shows a warning when it can tell.

## 7. What we would like back

- Your decision: approved, approved with conditions (please list them), or not approved, and what would change it.
- Your decisions on section 4, and any wording you require in the materials.
- Your view on section 5's two questions (the cooling-off with screening; the researcher's role).

Nothing you say will be restated as stronger approval than you gave. Your conclusions will be recorded as the
review GATE-016 requires.
