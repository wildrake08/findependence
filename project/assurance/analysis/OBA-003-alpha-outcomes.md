# OBA-003: first Capabilities for the remaining Outcomes, scoped to the alpha

ACT-001 asked to continue development until the Outcomes are completed for the alpha (REV-037).

## What "completed" can mean in the alpha

An Outcome is achieved only if real households' lives change; claiming that needs Subject evidence
that only ACT-001 or a designated reviewer may qualify (CP-004), and the alpha uses made-up data only
(REV-034). So in the alpha an Outcome counts as **covered** when at least one accepted Capability
contributes to it and is built and tested, as OUT-002 and OUT-005 already are. Achievement is for
STUDY-001 and later.

Capabilities need ACT-001's acceptance (CP-002 delegates only Functions, Mechanisms, and
Requirements). This analysis proposes; nothing is built until they are accepted.

## The seven uncovered Outcomes

| Outcome | First Capability that fits a local, consent-governed, evaluation-free alpha | For the alpha? |
|---|---|---|
| **OUT-001 Legibility**: understand the current and projected situation | **CAP-007 Monthly picture and projection.** Across the items a member can see: money in and out each month, and how that runs over the next 12 months if nothing changes (repeating items recur on their schedule; one-offs are not projected). No advice, no judgment. | **Yes.** It builds directly on the frequency work (CP-007, CP-012). |
| **OUT-004 Coordination**: shared decisions and obligations, fairly | **CAP-008 Agreed shares of joint items.** Owners of a jointly owned item can agree how its amount is split among them (for example rent 60/40); each owner's totals count their share, and changing the split needs every owner's agreement. Today each joint owner counts the whole amount. | **Yes.** It uses the existing request-and-agree machinery. Tension with OUT-005 (DEF-015) is handled by unanimity, as for other joint changes. |
| **OUT-007 Optionality**: avoid lock-in | **CAP-009 Take your record somewhere new.** A member can bring their own export into a new household file, as items and values they own, with their links, so their record isn't locked into one household. | **Yes.** The export exists (CAP-002); this completes the round trip. Imported data is untrusted input and is validated strictly. |
| **OUT-003 Means**: obtain entitlements on fair terms | Entitlement information (benefits, credits) for the deployment context. | **No.** It would present jurisdiction guidance, and the Washington notes' professional check is deferred until after the alpha (REV-034). Presenting unchecked guidance could mislead. |
| **OUT-006 Resilience**: absorb shocks | How many months savings would cover obligations. | **No.** It needs balances (what you have and owe), which items don't record yet. A later OUT-001 Capability for balances comes first. |
| **OUT-008 Continuity**: transitions (joining, separation, death, incapacity) | Joining (CP-009 B); succession or emergency access. | **No.** Both change key handling; CP-009 A deferred joining until after the security review, and succession adds normative questions (who may act for whom) that need ACT-001. |
| **OUT-009 Bounded burden** | CAP-006 low-effort upkeep. | **No.** ACT-001 deferred CAP-006 pending usage evidence (REV-005); STUDY-001 Q5 measures burden. |

## Recommendation

Accept CAP-007, CAP-008, and CAP-009 for the alpha, and build them in that order (smallest and most
foundational first). Record the other four as deferred, with the reasons above, so the alpha's
coverage is explicit: OUT-001, OUT-002, OUT-004, OUT-005, OUT-007 covered; OUT-003, OUT-006, OUT-008,
OUT-009 deferred.

Each accepted Capability would get Functions, Mechanisms, and Requirements (delegated under CP-002),
a WorkItem, tests with mutation checks, and a release note for the next alpha version.
