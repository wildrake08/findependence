# ORIENT-001 — Foundation Orientation Analysis

- **Artifact type:** analysis output (EvidenceCandidate source; see `EVC-001`)
- **Produced by:** ACT-002 (AI agent) acting as AUT-SEMANTIC-ARCHITECT / AUT-SEMANTIC-CRITIC
- **Authority:** proposal/advisory only. Nothing here canonicalizes any artifact.
- **Date:** 2026-09-25
- **Canonical inputs:** `CONSTITUTION.md`, `GOVERNANCE.md`, `AGENTS.md`, `PROMPT.md`, `project/bootstrap.yaml` (version 1, commit 0ab85fc), `project/manifest.yaml` (commit 0ab85fc), `framework/**` (version 1)
- **Subjects of analysis:** SUBJ-001, TEL-001, PUR-001 (all `proposed`)

Supplied wording (preserved verbatim; not altered by this analysis):

| ID | Statement | Supplied by |
|---|---|---|
| SUBJ-001 | Every household, and every person within each household. | `prior_project_foundation` |
| TEL-001 | Every household, and everyone in it, free to pursue the life they value, not held back by money. | `initiating_human` |
| PUR-001 | Increase the effective capacity of households and their members to deliberately shape their economic lives in service of the lives they value. | `initiating_human` |

---

## 1. Subject (SUBJ-001)

### 1.1 Does it identify whose condition ultimately matters? — Yes (CLM-001)

It names the bearers of the condition that justifies the system. It does not name users, customers, or operators. So **Subject ≠ user** (ASM-007). The Subject is universal in scope. The System's reach will always cover a proper subset of it. That's appropriate at this level, but it means later Claims must never equate "users served" with "Subject condition improved".

### 1.2 Do household and member remain separately meaningful? — Yes, and this is a strength

The conjunction "Every household, **and** every person within each household" makes two distinct levels of Subject:

- **household-level condition:** shared economic life, joint resources, collective plans;
- **member-level condition:** each person's own freedom to pursue the life *they* value.

Neither level is defined as an aggregate of the other. That matters because the member level can't be dissolved into a household average.

### 1.3 Ambiguities and boundary conditions

| # | Issue | Material? | Disposition |
|---|---|---|---|
| S-a | **"Household" is undefined.** It could mean co-residence, shared finances, kinship, or tax/benefit unit, and each gives a different Subject population. | Yes | Interpretive qualification Q1 (ASM-001) |
| S-b | **Persons outside any household.** Unhoused, institutionalized (prison, residential care), and some displaced persons are excluded on a literal residential reading. They are among those most held back by money. | Yes | DEF-001. Mitigated by Q1 (a household is an economic unit of one or more persons, whatever their housing status) |
| S-c | **Multi-household membership.** Shared-custody children, students, and people who send remittances to or support kin in another household. | Moderate | ASM-002: a person may be a member of more than one household |
| S-d | **Single-person households.** Household and member coincide. | No | Coherent degenerate case |
| S-e | **Members without economic agency.** Infants, dependents, and people with diminished capacity. Their condition matters, but they may never be Actors. | Moderate | Carried to Outcome breadth (agency vs. condition) |
| S-f | **Provenance.** The Subject is marked `supplied_by: prior_project_foundation`, which is not present in this repository and can't be verified. | Yes (authority) | ASM-009. Ratification by the initiating human should adopt it on their own authority |

---

## 2. Telos (TEL-001)

### 2.1 Is it an ultimate desired Subject condition rather than a product feature? — Yes (CLM-002)

It describes a condition of the Subject ("free to pursue the life they value"). It names no system, feature, or mechanism, and it is Subject-scoped at both levels ("every household, and everyone in it"). Its `concerns` relationship to SUBJ-001 is exact.

### 2.2 Does it improperly imply…

| Risk | Finding |
|---|---|
| **Elimination of scarcity** | *Literal risk present* (DEF-003). "Not held back by money", read absolutely, would mean no one ever faces a budget constraint, which is unattainable. The coherent reading is that **money is not the decisive barrier** to pursuing a valued life. Trade-offs and scarcity remain. Recommended as interpretive qualification Q2 (ASM-004). The Telos is **regulative** (a direction of improvement), not a terminal state the system claims to reach. |
| **Guaranteed outcomes** | *No.* "Free to **pursue**" is about opportunity and agency, not attainment. This is well-formed. |
| **System-defined valued lives** | *No, as worded.* "The life **they** value" puts valuation in the Subject. This rules out paternalistic optimization toward system-chosen goals (Principle candidate PRI-001). |

### 2.3 Ambiguities and tensions

- **T-a. The referent of "they".** "The life they value" could mean the household's collectively valued life or each member's own. Those can conflict (for example one partner's career move against another's caregiving). The Telos doesn't say which prevails. This is inherited by DEF-002.
- **T-b. Adaptive preferences** (DEF-007, low severity). People under long-term deprivation may come to value less. A purely subjective reading can hide how much they are held back. This doesn't block ratification, but assurance shouldn't rely only on stated satisfaction as evidence of Telos progress.
- **T-c. "Money" is narrower than "economic life".** The Telos names money as the constraint. The Purpose addresses economic life, which also covers time, work, care, housing, and in-kind benefits. This is coherent, because economic life is the domain through which money constrains. It is not a defeater, but Outcome breadth should include non-monetary economic dimensions.

---

## 3. Purpose (PUR-001)

### 3.1 Is it a bounded system contribution rather than the Telos itself? — Yes (CLM-003)

- The Telos is an **end condition**. The Purpose is a **directional contribution** ("increase … capacity"). It doesn't claim to achieve the Telos, so the Purpose→Telos relationship is `advances`, not identity.
- Its object is bounded: **the Subject's effective capacity to deliberately shape their economic lives**. It is not "their economic outcomes", "their wealth", or "their happiness".
- It is agency-preserving. The system strengthens the Subject's own shaping and doesn't do the shaping for them (Principle candidate PRI-003).

### 3.2 Broader than a feature, yet realizable by a designed system? — Yes, with qualification

- **Broader than a feature:** yes. It could be realized through many Capabilities (legibility, planning, coordination, optionality, resilience, access to means), none of which is privileged.
- **Realizable:** at least in part. A designed system can plausibly increase legibility, foresight, coordination, and optionality. Whether it also covers **means** (income or resource access) depends on how "effective capacity" is read. ASM-005 reads it as covering access to means as well as knowledge and tools, because capacity without means isn't *effective*.
- **Assurability gap:** "effective capacity" is hard to measure. Before any Capability Claim can be supported, Outcome-level assurance will need an explicit operationalization. This is an evidence gap, not a defect, and it is carried to Outcome breadth and sentinel selection.

### 3.3 Tensions

- **P-a. Deliberation burden** (DEF-005). "Deliberately shape" could be read as requiring continuous active deliberation. Time, attention, and cognitive bandwidth are themselves scarce, most of all for constrained households. Qualification Q3 (ASM-006): *deliberately* covers the Subject's capacity to choose to delegate, automate, or not attend to matters. Deliberateness sits at the level of chosen policy, not every transaction.
- **P-b. Capacity vs. means** (DEF-004). Where the binding constraint is absolute insufficiency of means, greater capacity to shape may contribute little. Capacity tools also tend to benefit already-advantaged households most (a Matthew effect). That sits in tension with "every household". It doesn't block ratification, but it must be carried forward as an equity-of-contribution concern for Outcomes and assurance.

---

## 4. Mutual coherence (CLM-004)

```
SYS-001 (System) —has_purpose→ PUR-001 —advances→ TEL-001 —concerns→ SUBJ-001
```

| Pair | Coherent? | Notes |
|---|---|---|
| Subject ↔ Telos | Yes | Same dual-level scope, word for word ("every household, and everyone in it") |
| Telos ↔ Purpose | Yes, partial by design | The Purpose addresses one causal route to the Telos (the Subject's own capacity). It doesn't claim to change structural determinants such as wages, prices, or policy. That is appropriate for a bounded Purpose. |
| Purpose ↔ Subject | Yes | "households and their members" matches the Subject's dual level |
| Shared valuation | Yes | Telos and Purpose both use "the lives they value", so the valuation authority is consistent |

**Main cross-cutting tension (DEF-002): household vs. member.** All three artifacts name both levels, but none gives a rule for when they conflict. The key failure mode is concrete. Increasing a *household's* capacity to shape its economic life can increase one member's capacity to **control, surveil, or restrict** another (financial abuse and coercive control). That would reduce the Telos for the affected member while appearing to advance it for the household. Without a governing principle, the Purpose could be satisfied at household level while being defeated at member level.

The recommended qualification is a candidate normative principle, **PRI-002 (member non-subordination)**: household-level capacity gains don't justify reducing any member's agency, and a member's condition isn't reducible to the household aggregate. This needs human ratification because it is a foundational normative principle under GOVERNANCE.md.

---

## 5. Normative, authority, and contextual issues (CLM-005, CLM-006)

### 5.1 Normative constraints (materially relevant)

- **Non-paternalism** (PRI-001): the Subject defines valued lives.
- **Member non-subordination** (PRI-002): see §4.
- **Agency preservation with chosen delegation** (PRI-003): the system augments the Subject's decisions and doesn't supplant them. Any delegation is chosen by the Subject.
- **Privacy and consent within households** (candidate constraint, not yet elevated). Member financial data is personal to the member even inside a household. This is carried into Outcome breadth and handled as a derived Constraint under PRI-002.

### 5.2 Legitimacy of the foundation

One initiating human is setting a Telos about "every household". This is legitimate as a **project orientation**, meaning what this project aims at. It is not a claim of authority over households, and the ratified foundation should be read that way. There is currently no representation of the Subject in governance. That doesn't block ratification, but it is noted for later assurance of "value" claims.

### 5.3 Context

Jurisdiction, regulatory regime (financial-advice regulation, data protection, open banking/data access), and deployment context are all unspecified (CTX-001). This **doesn't block foundation ratification** because Subject, Telos, and Purpose are context-independent as worded. It **will block** Requirement canonicalization for any Mechanism that touches financial data or advice.

### 5.4 Process and authority findings (repository state)

These don't affect the semantic soundness of the foundation. They do affect whether the canonicalization gates can be legitimately evaluated (CLM-006):

- **DEF-008:** `scripts/check` is an unimplemented placeholder (exit 2). All three foundational gates require `deterministic_checks: [check]`, so they can't be satisfied as specified. The interim orientation check (`project/assurance/checks/orientation_check.exs`) is **not** the registered `AUT-CHECK` automation, and it has no authority to stand in for it.
- **DEF-009:** the gates require the `specified → canonical` transition, but no authority policy governs `proposed → coherent → specified` for foundational artifacts. The AI has therefore left SUBJ/TEL/PUR in `proposed` and recorded its coherence assessment separately.
- **DEF-010:** `project/bootstrap.yaml` is wrapped in a markdown code fence and doesn't parse as YAML. Its content was read after stripping the fence. The file hasn't been changed.
- **DEF-011:** the initiating Actor is recorded only as `me`. The repository commit author is `wildrake08` / git user "William Drake". The actor's identity for authority records isn't confirmed.

---

## 6. Conclusion

**No semantic defeater blocks ratification.** Under the interpretive qualifications Q1–Q3 and principle candidates PRI-001–003, Subject, Telos, and Purpose form a coherent foundation that can be ratified. None of these qualifications changes the supplied wording.

**Canonicalization is procedurally blocked** by DEF-008 and DEF-009 until the initiating human decides how the gate's deterministic-check requirement and the pre-canonical state transitions are handled.

### Interpretive qualifications (no change to wording)

- **Q1 (SUBJ-001):** a "household" is an economic unit of one or more persons who share some part of their economic life, regardless of housing status or residence. A person may belong to more than one household.
- **Q2 (TEL-001):** "Not held back by money" means money is not the decisive barrier to pursuing a valued life. It doesn't imply unlimited resources or the end of trade-offs. The Telos is regulative.
- **Q3 (PUR-001):** "Deliberately shape" includes the Subject's capacity to choose to delegate, automate, or not attend. "Effective capacity" includes access to means as well as knowledge, legibility, and tools.
- **Q4 (all):** Household-level condition never substitutes for member-level condition (see PRI-002).
- **Q5 (all):** The Subject is not the user population. Improvement is judged against the Subject, including those the system doesn't reach, and with attention to how contribution is distributed across households (DEF-004).
