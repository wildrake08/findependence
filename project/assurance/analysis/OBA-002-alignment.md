# OBA-002: Sentinel 2, OUT-002 Alignment

- **Artifact type:** analysis output (EvidenceCandidate source; see `EVC-020`)
- **Produced by:** ACT-002 as AUT-SEMANTIC-ARCHITECT / AUT-SEMANTIC-CRITIC. Proposal only.
- **Date:** 2026-09-26
- **Inputs:** OUT-002 (specified), PRI-001..003 (canonical), ASM-012, DEF-007, DEF-015, OUT-005 and OUT-009 (specified), core/ at 7b9dcf6

## 1. What OUT-002 asks, and what it forbids

OUT-002 reads: *"Economic activity … serves what the household and each member value, **as they themselves define it**."*

**What makes it hard.** The System has to help activity line up with values without ever:

- defining, ranking, or grading those values (PRI-001);
- letting household values override a member's (PRI-002, ASM-012);
- adding so much reflective work that it crowds out the life being valued (OUT-009, DEF-005).

**The trap: an alignment score.** A score presupposes a standard of "aligned" that the System would have to own, which is paternalism under another name. The design below therefore gives the Subject **legibility of the relationship between activity and their own stated values**, and **makes no judgment of it**.

## 2. Proposed Capabilities (all proposed; each `contributes_to → OUT-002`)

| ID | Capability | Why it is needed |
|---|---|---|
| CAP-003 | **Value articulation.** Each member can record what they value, in their own words, as items they own. These are private by default under the CAP-001 visibility model. The System never supplies, suggests, or ranks values. | Without stated values, there is nothing for activity to align with. Making values owned items reuses CAP-001 and so inherits member standing. |
| CAP-004 | **Activity–value linking.** A member can relate the economic items they can see to their own values, and see, only across what is visible to them, how activity is distributed over those values. No evaluation is made. | This is the core of alignment legibility. REQ-106-style visibility scoping prevents leakage through the distributions. |
| CAP-005 | **Shared commitments by consent.** Members can create shared values or commitments, such as a joint goal, that exist only while every participant consents. Any participant can withdraw, and individual values are never overridden. | This answers ASM-012 structurally: the System never decides whose values prevail, and shared values exist only by unanimous, revocable consent (the same semantics as REQ-103 and REQ-107). |
| CAP-006 | **Low-effort upkeep.** Linking and revising can be done in bulk, by rules the member chooses, and ignored without penalty. | OUT-009 and PRI-003: deliberateness means choosing a policy, not reviewing every transaction. |

**Not proposed.**

- **Recommendations toward values.** These need a model of what serves a value, which risks both paternalism and regulated advice (CTX-001).
- **Nudges and reminders.** They add burden, and their normative defaults would be the System's.

These may return later as Mechanisms under CAP-006, and only by the member's choice.

## 3. First slice for sentinel 2: CAP-003 + CAP-004 (deployment-free, extending core/)

| Level | Proposed |
|---|---|
| Functions | FUN-009 record a value in one's own words (enables CAP-003) · FUN-010 link a visible item to one of one's own values, and unlink it (CAP-004) · FUN-011 show the distribution of one's visible activity across one's own values, with no evaluation (CAP-004) |
| Mechanisms | MEC-008 values as owned items of kind `value`, reusing MEC-004/MEC-002 (realizes FUN-009) · MEC-009 per-member link set, where links belong to the member who made them and are never visible to anyone else (FUN-010) · MEC-010 a visibility-scoped distribution computed only over the requester's visible items and own links, returning amounts and counts but no score, rank, or label (FUN-011) |
| Requirements | See the table below |

| ID | Candidate Requirement | From |
|---|---|---|
| REQ-111 | A value shall be an item of kind `value`, created and owned by a member and subject to REQ-101..REQ-110 like any other item. The System shall provide no predefined values. | MEC-008, PRI-001 |
| REQ-112 | A member shall be able to link, and unlink, any item visible to them to any value visible to them. Links shall belong to that member, and no other member shall ever be able to read them. | MEC-009, PRI-002 |
| REQ-113 | The value distribution for a member shall be computed only over items visible to that member and that member's own links. It shall report per-value sums and counts, plus an explicit unlinked remainder, and shall contain no score, rank, threshold, or evaluative label. | MEC-010, PRI-001, PRI-002 |
| REQ-114 | Losing visibility of an item or value (revocation, relinquishment, deletion, departure) shall silently remove it from the member's distribution. The member's link records shall not reveal anything about the invisible item. | MEC-009, MEC-010, PRI-002 |

**Why links are private (REQ-112).** Links are private even when both the item and the value are shared. How one member relates shared spending to their own values is itself personal information (PRI-002). CAP-005 is where shared interpretations belong, and there they exist only by consent.

## 4. Assumptions, defeaters, and questions

- **ASM-017.** Alignment legibility without evaluation is a sufficient first contribution to OUT-002. Whether seeing the distribution actually changes anything is a Capability- or Outcome-level question that needs Subject observation (CTX-001).
- **DEF-022 (DEF-007 made concrete).** A member whose stated values have adapted to deprivation will see "good alignment" with a diminished life. The design deliberately does not correct for this, because correcting it would be paternalism. This limit of OUT-002 is accepted, not solved.
- **DEF-023.** Private links mean two members can interpret the same shared expense very differently without either knowing. That is protective (PRI-002) but may hinder coordination (OUT-004). CAP-005 is the consent-based bridge.
- **Question for ACT-001: ASM-012 resolution.** CAP-005 proposes that the System *never* decides whose values prevail, and that shared values exist only by unanimous, revocable consent. This settles ASM-012 structurally, but it is normative, so it is ACT-001's to accept or reject.
