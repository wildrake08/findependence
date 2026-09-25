# Findependence — Autonomous Bootstrap Instruction

You are operating inside a repository governed by the Canonical Software-System Lifecycle Bootstrap Framework.

Your job is to advance **Findependence** autonomously as far as legitimate authority, available evidence, and deterministic validation permit.

## 1. Read canonical operating context

Before acting, read in this order:

1. `CONSTITUTION.md`
2. `GOVERNANCE.md`
3. `AGENTS.md`
4. `project/bootstrap.yaml`
5. `project/manifest.yaml`
6. `framework/readiness/canonical.md`
7. `framework/vocabulary/artifacts.yaml`
8. `framework/vocabulary/relationships.yaml`
9. `framework/invariants/core.yaml`
10. `framework/states/machines.yaml`
11. `framework/gates/foundational.yaml`
12. applicable project artifacts thereafter

Treat repository state as authoritative over conversation history.

Do not use hidden conversational assumptions as canonical project state.

---

# 2. Bootstrap Findependence

Use `project/bootstrap.yaml` as the initiating input.

Create or update the governed project substrate necessary to enter orientation.

Capture:

- project identity;
- Idea;
- initiating Actor;
- initial authority context;
- provenance of all supplied foundation inputs.

Do not fabricate missing canonical state merely to satisfy a schema.

---

# 3. Foundation supplied by the initiating human

The following foundation statements have already been supplied.

## Subject candidate

> Every household, and every person within each household.

## Telos candidate

> Every household, and everyone in it, free to pursue the life they value, not held back by money.

## Purpose candidate

> Increase the effective capacity of households and their members to deliberately shape their economic lives in service of the lives they value.

Preserve the supplied Telos and Purpose wording exactly unless the initiating human explicitly authorizes a change.

You may critique, analyze, qualify, interpret, or identify implications of these statements.

You may not silently replace them with alternative wording.

---

# 4. Orientation work

Autonomously perform the analysis required to determine whether the supplied Subject, Telos, and Purpose form a coherent canonical foundation.

Evaluate at minimum:

- whether the Subject identifies whose condition ultimately matters;
- whether household and individual members remain separately meaningful;
- whether the Telos describes an ultimate desired Subject condition rather than a product feature;
- whether the Telos improperly implies elimination of scarcity, guaranteed outcomes, or system-defined valued lives;
- whether the Purpose is a bounded system contribution rather than the Telos itself;
- whether the Purpose is broader than a feature but sufficiently realizable by a designed system;
- whether Subject, Telos, and Purpose are mutually coherent;
- whether any material normative, authority, or contextual issue blocks ratification.

Identify:

- assumptions;
- ambiguities;
- boundary conditions;
- tensions;
- possible defeaters;
- materially relevant normative constraints.

Do not create unnecessary new foundational concepts.

---

# 5. First human gate

After completing orientation analysis, stop at one consolidated:

`HUMAN_GATE_REQUIRED`

Present:

1. proposed canonical Subject;
2. proposed canonical Telos;
3. proposed canonical Purpose;
4. interpretation and boundaries of each;
5. their relationships;
6. material assumptions;
7. material uncertainties or defeaters;
8. any recommended qualification that does not alter the supplied wording;
9. the exact decision required from the initiating human.

Request one of:

- `RATIFY`
- `RATIFY WITH QUALIFICATIONS`
- `REVISE`
- `REJECT`

Do not canonicalize these artifacts yourself.

---

# 6. After foundation ratification

Once the initiating human ratifies the foundation, continue autonomously.

Do not repeatedly ask whether to continue.

Proceed through:

Subject  
→ Telos  
→ Purpose  
→ Outcome breadth  
→ sentinel selection  
→ Capability  
→ Function  
→ Mechanism  
→ Requirement  
→ architecture only where required  
→ bounded WorkItems  
→ Implementation Elements  
→ deterministic verification  
→ Claims  
→ EvidenceCandidates  
→ qualified Evidence  
→ Assessment  
→ runtime observation  
→ upstream reassessment where warranted

Use breadth before unnecessary depth.

---

# 7. Outcome breadth

Develop a materially adequate sibling set of Subject Outcomes before deeply implementing one branch.

Critically evaluate:

- overlap;
- missing dimensions;
- aggregation errors;
- household-versus-individual conflicts;
- agency;
- legibility;
- means;
- alignment;
- coordination;
- optionality;
- resilience;
- continuity where materially applicable.

Do not assume an existing Outcome taxonomy is correct merely because one has been suggested previously.

Reuse canonical artifacts only when supported by current project state.

---

# 8. Sentinel selection

Choose a high-information branch using approximately:

semantic importance  
× uncertainty  
× architectural novelty  
× evidence gap  
÷ cost of learning

Record why the branch was chosen.

Then deepen only enough to establish the first justified executable vertical slice.

---

# 9. Requirement rule

Every material Requirement must have an explicit upward justification path.

A Requirement without sufficient `derived_from` provenance must not be accepted merely because it seems useful.

Do not derive Requirements directly from UI ideas or implementation convenience when higher semantic justification is absent.

---

# 10. Implementation authority

AI may implement accepted Requirements only inside bounded WorkItems.

Before implementation, establish:

- objective;
- target Requirement(s);
- canonical input versions;
- allowed files/artifacts;
- authority scope;
- expected postconditions;
- required deterministic checks.

AI implementation authority does not include authority to rewrite upstream semantics.

---

# 11. When implementation discovers a problem

If implementation reveals that:

- a Requirement is ambiguous;
- a Mechanism is unsuitable;
- a Function is insufficient;
- a Capability is incorrectly modeled;
- an Outcome is incomplete;
- Purpose or higher semantics may be wrong;

do not rewrite upstream intent to make implementation easier.

Instead create an appropriate:

- Defeater;
- ChangeProposal;
- reassessment request;
- upstream reopening request.

Then stop only if legitimate authority or unresolved material ambiguity prevents continuation.

---

# 12. Validation

Prefer deterministic automation wherever verification can be reproducible.

The governing pattern is:

AI proposes or acts  
→ deterministic automation validates  
→ assurance evaluates  
→ human authority gates where required

A deterministic `PASS` means only that no applicable deterministic invariant failed.

It does not prove semantic, causal, normative, Capability, Outcome, Purpose, or Telos truth.

---

# 13. Assurance

Do not treat raw outputs as Evidence automatically.

Use:

runtime/test/analysis output  
→ EvidenceCandidate  
→ provenance/integrity/context qualification  
→ Evidence  
→ Claim binding  
→ Assessment

Evidence must distinguish:

## Integrity

- valid
- invalidated
- corrupt
- untrusted

## Applicability

- applicable
- partially_applicable
- inapplicable
- stale

Evidence may remain valid while becoming stale or inapplicable.

---

# 14. Runtime

RuntimeEvents are observations.

They do not automatically become Evidence.

Qualify them before using them to support or contradict Claims.

Runtime evidence may weaken or reopen upstream Claims and artifacts.

Preserve history.

---

# 15. Human governance

Stop only when one of these genuinely applies:

- `HUMAN_GATE_REQUIRED`
- `AUTHORITY_CONFLICT`
- `MATERIAL_AMBIGUITY`
- `UPSTREAM_DEFEATER`
- `OUT_OF_SCOPE`
- `DETERMINISTIC_FAILURE_REQUIRING_UPSTREAM_CHANGE`

Do not stop merely because:

- a new artifact needs creating;
- decomposition is required;
- architecture needs analysis;
- code needs writing;
- tests need running;
- deterministic failures can be repaired within current authority;
- additional critique is useful.

Continue autonomously in those cases.

---

# 16. Material completion report

Whenever reaching a genuine gate, report:

- current lifecycle state;
- artifacts created or changed;
- canonical inputs and versions used;
- traceability path;
- deterministic checks performed;
- Claims affected;
- EvidenceCandidates/Evidence created;
- assumptions;
- Defeaters;
- unresolved issues;
- exact required human decision.

Never represent work as complete when the required assurance or authority state has not actually been established.