# OBA-001: Outcome breadth, sentinel selection, and first-slice decomposition

- **Artifact type:** analysis output (EvidenceCandidate source; see `EVC-011`)
- **Produced by:** ACT-002 as AUT-SEMANTIC-ARCHITECT / AUT-SEMANTIC-CRITIC
- **Authority:** proposal only. Every artifact proposed here stays in `proposed` state.
- **Date:** 2026-09-25
- **Canonical inputs:** SUBJ-001, TEL-001, PUR-001, PRI-001..003 (canonical at daf4b43); REV-001 qualifications Q1–Q5; DEF-002, DEF-004, DEF-005, DEF-007; CTX-001

---

## 1. What an Outcome is here

An Outcome is a **condition of the Subject** (a household, a member, or both) that the System can contribute to and that, taken together with its siblings, makes up PUR-001's "effective capacity … to deliberately shape their economic lives in service of the lives they value".

This definition has three consequences:

- **An Outcome is not a feature.** "Has a budgeting tool" is not an Outcome.
- **An Outcome is not the Purpose restated.** If a candidate just says "the Subject has more capacity to shape its economic life", it is an aggregation error: it duplicates PUR-001 instead of decomposing it.
- **Every Outcome must say which Subject level it concerns.** Under Q4, a household-level Outcome never stands in for a member-level one.

## 2. The suggested dimensions, critically evaluated

`PROMPT.md` §7 lists agency, legibility, means, alignment, coordination, optionality, resilience, and continuity. It also warns against assuming a suggested taxonomy is correct. Each dimension is judged below.

| Dimension | Verdict | Reason |
|---|---|---|
| Agency | **Rejected as a sibling** | "Capacity to deliberately shape" *is* agency. As a sibling Outcome it would restate the Purpose, which is an aggregation error. Agency instead works as a cross-cutting constraint through PRI-003. |
| Legibility | Kept (OUT-001) | Deliberate shaping requires understanding the current and projected situation. |
| Alignment | Kept (OUT-002) | "In service of the lives they value" means economic activity should serve Subject-defined ends (PRI-001). |
| Means | Kept (OUT-003) | Q3 says effective capacity includes access to means. DEF-004 shows that leaving means out would skew benefit toward households that are already advantaged. |
| Coordination | Kept (OUT-004) | Households act jointly, and many also carry obligations to other households (Q1: people can belong to several households; remittances; care for kin). |
| Optionality | Kept (OUT-007) | Keeping future options open is distinct from absorbing shocks: it concerns forward choice, not downside protection. |
| Resilience | Kept (OUT-006) | Shocks, including exploitation (scams, predatory terms, coercion), are a primary way money holds people back. |
| Continuity | Kept (OUT-008), narrowed | Resilience already covers external shocks. Continuity is kept for **structural transitions of the household itself**: members joining or leaving, separation, death, incapacity, and changes in who manages. |

### Missing dimensions found

- **Member economic standing (OUT-005).** This is the most material gap. DEF-002 and PRI-002 require that each member hold an independent, protected economic position inside the household: their own information, their own resources, a voice, and the possibility of a safe exit. It is not coordination, because coordination is the household acting together and standing is the individual protected within it. The two can be in genuine tension (DEF-015).
- **Bounded burden (OUT-009).** DEF-005 and Q3 establish that time, attention, and money-related stress are themselves scarce. When managing economic life crowds out the life being valued, the Telos is not served, even if every other Outcome improves.

### Considered and rejected

- **Financial literacy or knowledge.** This is a *means* to legibility and agency, not a condition valued for its own sake. It belongs at Capability or Mechanism level.
- **Wealth or net worth.** Q2 establishes that the Telos is not "more money", and a wealth Outcome would pull toward system-defined valued lives (PRI-001). What matters is captured by Means, Resilience, and Optionality.
- **Wellbeing or happiness.** This sits above the Purpose. It belongs near the Telos, and the System's contribution to it is only indirect.

## 3. Proposed sibling set

Every Outcome below has a `contributes_to → PUR-001` relationship.

| ID | Outcome (Subject condition) | Level |
|---|---|---|
| OUT-001 | **Legibility.** The household and each member can understand their current and projected economic situation (resources, obligations, flows, entitlements, risks) well enough to decide. | both |
| OUT-002 | **Alignment.** Economic activity (spending, saving, earning, borrowing, giving) serves what the household and each member value, as they themselves define it. | both |
| OUT-003 | **Means.** The household and each member obtain the resources they are entitled to or could reasonably obtain, on fair terms. | both |
| OUT-004 | **Coordination.** The household can make and carry out shared economic decisions and obligations, including obligations to other households, fairly and without depending on any one member. | household |
| OUT-005 | **Member standing.** Each member has an independent, protected economic standing: their own information, their own resources, a voice in shared matters, and the ability to leave safely. | member |
| OUT-006 | **Resilience.** The household and each member can absorb and recover from economic shocks and exploitation without being forced off the life they value. | both |
| OUT-007 | **Optionality.** The household and each member keep and expand their future economic options, and avoid lock-in that forecloses valued lives. | both |
| OUT-008 | **Continuity.** Economic life stays coherent and manageable through structural household transitions (joining, leaving, separation, death, incapacity, change of manager), for the household and for each member individually. | both |
| OUT-009 | **Bounded burden.** Managing economic life does not crowd out the life being valued, in time, attention, or stress. | both |

### Checks on the set

- **Overlap.** Four pairs look similar but are distinct.
  - OUT-006 vs OUT-007 differ in direction: downside versus upside. They share instruments such as buffers, which is overlap at Mechanism level, not Outcome level.
  - OUT-004 vs OUT-005 differ in Subject level and are deliberately in tension.
  - OUT-001 vs OUT-002: alignment depends on legibility, but the two are not the same.
  - OUT-006 vs OUT-008 differ in cause: external shock versus structural transition.
- **Aggregation errors.**
  - Agency was removed because it restated the Purpose.
  - OUT-004 is household-level, but PRI-002 constrains it: coordination bought at a member's expense does not count.
  - "Both"-level Outcomes must be assessed per member as well as per household (Q4).
- **Household vs. individual conflicts.** The sharpest conflict is OUT-004 against OUT-005, recorded as DEF-015. There is a subtler one inside OUT-002: the household's values and a member's values may diverge, and PRI-001 does not say whose prevail. That question is left open at Outcome level as ASM-012.
- **Completeness.** Under Q2 and Q3, the set covers the named ways money holds people back:
  - insufficiency: OUT-003
  - opacity: OUT-001
  - misdirection: OUT-002
  - fragility: OUT-006
  - lock-in: OUT-007
  - disruption: OUT-008
  - intra-household subordination: OUT-005
  - overload: OUT-009
  - joint-action failure: OUT-004

  No materially distinct mode is left uncovered, at least as far as this single-agent analysis can see (DEF-017).
- **Evidence gap.** Every one of these Outcomes is hard to measure. DEF-007 (adaptive preferences) affects OUT-002 especially.

## 4. Sentinel selection

The score is semantic importance × uncertainty × architectural novelty × evidence gap ÷ cost of learning, each rated 1–5. The ratings are judgments, not measurements (DEF-017).

| Outcome | Imp | Unc | Nov | Gap | Cost | Score |
|---|---|---|---|---|---|---|
| OUT-005 Member standing | 5 | 4 | 5 | 5 | 3 | **167** |
| OUT-002 Alignment | 5 | 5 | 4 | 5 | 4 | 125 |
| OUT-001 Legibility | 5 | 3 | 4 | 3 | 2 | 90 |
| OUT-004 Coordination | 4 | 4 | 4 | 4 | 3 | 85 |
| OUT-003 Means | 5 | 3 | 3 | 4 | 5 | 36 |
| OUT-008 Continuity | 3 | 3 | 4 | 4 | 4 | 36 |
| OUT-009 Bounded burden | 4 | 3 | 3 | 3 | 3 | 36 |
| OUT-006 Resilience | 4 | 3 | 2 | 3 | 3 | 24 |
| OUT-007 Optionality | 3 | 4 | 2 | 4 | 4 | 24 |

**Selected: OUT-005 Member standing (SYN-001).**

- **Importance.** It carries the only canonical principle aimed at a concrete harm (PRI-002, DEF-002). If the System gets this wrong, it can make the Telos *worse* for a member while appearing to help the household.
- **Architectural novelty.** Once any household data exists, the question of who owns and who sees each item shapes every later branch. Retrofitting per-member visibility is costly and error-prone. Settling it first therefore removes the most architectural risk.
- **Uncertainty.** The main open question is how joint ownership and consent should work without blocking coordination (DEF-015).
- **Cost of learning.** Moderate. The first slice needs no external data, no advice, and no deployment (§6), so CTX-001 does not block it.
- **Runner-up.** OUT-002 Alignment has higher uncertainty, but learning about it needs research with Subjects, which is costly. It is the recommended second sentinel.
- **Dependency, not merger.** The slice necessarily includes a minimal record of economic items, which also serves OUT-001. That is recorded as a dependency, not as a merged Outcome.

## 5. Sentinel branch decomposition (all proposed)

**Capabilities** (`contributes_to → OUT-005`):

- **CAP-001 Consent-governed visibility.** Each member holds economic information that is theirs and decides which other members may see it. Jointly held items are visible to all their holders. *(first slice)*
- **CAP-002 Independent exit.** A member can extract their own economic record and leave a household arrangement without any other member's cooperation. *(identified, not deepened)*

**Functions** (`enables → CAP-001`, `required_of → SYS-001`):

- **FUN-001** Record economic items with an owner set, which may be individual or joint.
- **FUN-002** Grant and revoke visibility of an item to specific members, under owner control.
- **FUN-003** Present each member only the items, and aggregates of items, visible to them.
- **FUN-004** Make every ownership and visibility change known to the item's owners.

**Mechanisms** (`realizes`):

- **MEC-001 Owner-set item model** (→ FUN-001). Every item has a non-empty owner set. The owner set changes only with the consent of all current owners.
- **MEC-002 Deny-by-default visibility policy** (→ FUN-002, FUN-003). `visible(item, m) ⇔ m ∈ owners(item) ∪ grantees(item)`. The policy is evaluated at every read, including reads that compute aggregates.
- **MEC-003 Per-item append-only change ledger** (→ FUN-004). The ledger is readable by the item's current owners.

**Candidate Requirements** (each `derived_from` its Mechanism and PRI-002):

| ID | Requirement | From |
|---|---|---|
| REQ-101 | Every economic item shall have a non-empty set of owning members; an item without owners shall be rejected. | MEC-001 |
| REQ-102 | A member shall be able to read an item if and only if they are one of its owners or hold an active grant for it. | MEC-002, PRI-002 |
| REQ-103 | Only an owner may create or revoke a grant. Creating a grant on a jointly owned item requires the consent of every owner; any single owner may revoke one. | MEC-002, PRI-002 |
| REQ-104 | An item's owner set shall change only with the consent of all current owners; no member may add themselves as an owner. | MEC-001, PRI-002 |
| REQ-105 | Every ownership change, grant, and revocation shall be recorded append-only and be readable by every current owner of the item. | MEC-003 |
| REQ-106 | Any household-level view or aggregate shall be computed only over items visible to the requesting member, so that no totals leak information from invisible items. | MEC-002, PRI-002 |

REQ-103's rule for joint items has normative content. It makes exposure require consent from every owner while letting any single owner withdraw it, which is the protective default under PRI-002. The cost is that one owner can block sharing, which is exactly the tension recorded as DEF-015.

## 6. Architecture, only where required

The first slice is a **deployment-free domain core**. It is a library that holds household items, owners, grants, and ledgers, and it enforces REQ-101..106. It has no data acquisition, no network, no persistence beyond the caller's own, and no advice.

- **Why this boundary.** It keeps CTX-001 (jurisdiction, financial-data and advice regulation, data protection) out of the critical path for learning. CTX-001 will bind as soon as the core is deployed or connected to real financial data.
- **Why Elixir.** It is the repository's established stack. This is not a claim that Elixir is the right runtime for the eventual System.

## 7. New assumptions and defeaters

- **ASM-012.** When household and member values diverge (OUT-002), PRI-001 does not settle whose prevail. This is left open at Outcome level.
- **DEF-015.** OUT-004 conflicts with OUT-005. Requiring all owners' consent (REQ-103, REQ-104) can block legitimate joint action, and letting any owner revoke can disrupt shared arrangements.
- **DEF-016.** The System cannot detect **coerced consent**. A member pressured outside the System can "grant" visibility or give up ownership. Consent-governed visibility is therefore necessary for OUT-005 but not sufficient. CAP-002 (independent exit) and ledger visibility (REQ-105) partly mitigate this.
- **DEF-017.** The Outcome set and the sentinel scores are a single agent's judgment, with no Subject input and no independent review.
