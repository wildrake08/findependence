# Governance

## Default authority model

### Human ratification required

- Subject
- Telos
- Purpose
- foundational normative principles
- constitutional governance changes
- changes that expand an automation's own authority
- resolution of materially contested authority where no prior authority governs

### AI may propose

AI may propose changes to any artifact within its read scope unless specifically prohibited.

Proposal authority never implies canonicalization authority.

### AI-agent implementation authority

AI agents may autonomously implement accepted Requirements when:

- the WorkItem explicitly grants implementation scope;
- canonical inputs have not changed;
- the change remains inside declared DecisionScope;
- applicable deterministic checks pass;
- no upstream semantic or governance change is required.

## Authority outcomes

- `allow` — established authority permits the action.
- `hold` — unresolved authority or required human action prevents advancement.
- `deny` — established authority excludes the action.

## Self-amendment

No automation may authorize an expansion of its own authority unless independently authorized by a pre-existing higher authority.
