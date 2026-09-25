# Canonical Software-System Lifecycle Bootstrap Kit

This repository is governed by a lifecycle framework that preserves traceability from executable implementation upward to the Subject whose condition ultimately justifies the system.

## Current maturity

- Framework: `foundation_ready`
- Reference kit: `reference_designed`
- RI-01 executable engine: **partial**. `check` is implemented (WI-001, `automation/ri01`, requires Elixir). The other commands are still placeholders.

## Start

1. Bootstrap the project.
2. Capture the idea.
3. Establish and gate Subject.
4. Establish and gate Telos.
5. Derive and gate Purpose.
6. Establish Outcome breadth.
7. Select a high-information sentinel branch.
8. Decompose Capability → Function → Mechanism.
9. Derive Requirements.
10. Create bounded implementation WorkItems.
11. Implement.
12. Run deterministic validation.
13. Qualify Evidence against explicit Claims.
14. Observe runtime behavior.
15. Reopen upstream work when evidence warrants it.

## Canonical commands

The RI-01 reference implementation will provide:

- `bootstrap`
- `check`
- `propose`
- `gate`
- `trace`
- `change`
- `status`

The placeholder scripts fail loudly so the repository does not falsely claim the rest of the RI-01 engine exists. `scripts/check --explain` prints how each invariant is interpreted.

## Foundational operating rule

Automation is broader than AI.

AI proposes/acts → deterministic automation validates → assurance evaluates → human authority gates where required.

## Core invariants

No material production implementation may be semantically orphaned.

Every material accepted system responsibility must either have a realization path or an explicit outstanding disposition.
