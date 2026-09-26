# STUDY-001: Local-first household observation study, protocol draft

- **Status:** APPROVED by ACT-001 (REV-007, 2026-09-26). Enrollment still requires independent ethics review, a professional check of the CTX-001 notes, and a reviewed prototype (section 9).
- **Authority basis:** REV-006 decision 3 (option a). Context: CTX-001 (Sumner, WA; local-first) and `CTX-001-washington-notes.md`.
- **Date:** 2026-09-26

## 1. Why

Every Claim above implementation level rests on assumptions that only real use can test. The Claims are CLM-012 (members experience CAP-001) and CLM-014 (CAP-003..006 suffice for OUT-002), and the hypothesis is ASM-017 (seeing alignment without evaluation helps). The Outcome set itself is DEF-017: one agent's judgment. This study is exploratory. It is meant to find where those assumptions are wrong, not to prove them right.

## 2. Questions

| # | Question | Tests |
|---|---|---|
| Q1 | Do members understand, and feel in control of, who in their household sees their economic information? | CLM-012, CAP-001, OUT-005 |
| Q2 | Do members understand that they could leave, and take their record with them, without anyone's help? Asked as a walkthrough; nobody is asked to actually leave. | CAP-002 |
| Q3 | Does seeing activity against their own stated values change their understanding or their decisions? Does it feel free of judgment? | ASM-017, CLM-014, PRI-001 |
| Q4 | Do consent rules (all-owner consent, private links) get in the way of doing things together? | DEF-015, DEF-023, OUT-004 |
| Q5 | How much time and attention does using it cost? | OUT-009, DEF-005 |

## 3. Design

Qualitative and small: **3–5 households** in or near Sumner, WA, each for **4 weeks**:

1. Private onboarding with each member.
2. A private check-in with each member in week 2.
3. A private exit interview with each member in week 4, plus an optional joint session if every member wants one.

The researcher is ACT-001 or someone ACT-001 designates.

## 4. Who takes part

- **Households with at least two adults (18+), each consenting individually.** Household dynamics are the point, so single-adult households are out of scope for this first study.
- **Adults only.** Children are not participants (CTX F3). Adults may record items that relate to children.
- **Exclusion for safety.** A household is not enrolled if any adult, asked privately, reports current fear of, or control by, another member. The prototype is not a security boundary (ASM-013, and DEF-025 unless it is resolved), and a study could raise the risk to exactly the people OUT-005 is meant to protect. Their needs are the reason for the design, but they should not be in the first test of it. Everyone asked receives the safety resources (§6), whatever they answer.

## 5. What is and isn't collected

| Collected by the researcher | Never collected |
|---|---|
| Interview notes: the participant's own words, typed or handwritten | Amounts, balances, transactions |
| Usability problems the researcher observes | Account numbers, credentials, identifiers |
| Time taken on a few set tasks | The contents of items, values, labels, links, or ledgers |
| Audio, **only** with every present person's consent (CTX W1) | Screenshots or exports of the app |
| | Health details (CTX W2); participants describe categories only |

All household data stays on the household's device. At the end, each member can use `Exit.delete` or `leave` on their own data, and the researcher confirms the device copy is removed if the participant asks.

## 6. Consent and withdrawal

- **Individual and private.** Each adult consents alone, never in front of another member, in plain language, and in writing.
- **Promises limited to what is true.** The prototype separates members' information within the app. Whether it protects against someone with access to the device depends on DEF-025. The consent form must state the chosen option's real limits (CTX W4, F1).
- **Withdrawal.** Any member can withdraw at any time, without giving a reason. The researcher does not tell other members why, or that it was that member's choice. The withdrawing member's notes are destroyed on request. The household may continue with the remaining adults if they wish.
- **Incentives** are paid to each adult individually, so no member controls another's payment (PRI-002).
- **Safety.** Every participant privately receives the National DV Hotline number (1-800-799-7233) and verified local Pierce County resources. If harm is disclosed, the researcher pauses that household's participation and offers resources.

## 7. The researcher's conduct

- **No advice** of any kind: no suggestions about spending, saving, or values (PRI-001, CTX W5).
- **No evaluation of anyone's alignment.** The researcher asks about experience and does not judge it.
- **Each member's information stays with that member.** Nothing one member says is repeated to another.

## 8. From observation to evidence

The pipeline follows `PROMPT.md` §13–14:

1. Each session's notes become an **observation record** (RuntimeEvent).
2. Each record becomes an **EvidenceCandidate** of kind `observation`, bound to the Claims it bears on.
3. Under CP-004 option B, only **ACT-001** (or a designated independent reviewer) may qualify observation Evidence and assess Claims above implementation level. ACT-002 may draft summaries but may not qualify them.

Contradicting evidence is expected. It will be recorded as a Defeater against the relevant Claim, Capability, or Outcome, and it may reopen upstream artifacts. This is the study working, not failing.

## 9. What must exist before the first household

1. A decision on DEF-025 (device and privacy architecture) and a prototype built to it.
2. A minimal interface over core/ for setup, items, grants, values, links, the distribution, export, and leave.
3. Consent and screening materials.
4. Verified local safety resources.
5. Ethics review and a professional check of the CTX-001 notes.
6. ACT-001's approval of this protocol.
