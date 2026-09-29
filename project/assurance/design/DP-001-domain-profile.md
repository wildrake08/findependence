<!--
DP-001: Findependence's domain profile under ARCH-003 section 37.
Status: DRAFT for ACT-001's ratification (WI-065, CP-020 U2, REV-084). Not in force until ratified.
Drafted by ACT-002, 2026-09-29, from ratified artifacts only; every rule cites its source. It changes no
Requirement, Capability, Mechanism, or Principle. Where the ratified artifacts do not settle something, it is
listed as open (section 12), not decided here.
-->

# DP-001 — Findependence domain profile

ARCH-003 is domain-neutral. This profile supplies what ARCH-003 §37 leaves to the product: the domain vocabulary,
domain contexts, canonical domain state, invariants, transitions, calculations, and the domain's own authorization,
audit, privacy, and assurance evidence. The platform's transport, trust, persistence, and execution semantics come
from ARCH-003, with ARCH-001 as the technology and security profile beneath it (REV-083 D1). The one declared
exception is the local-first form (section 10).

The profile serves SUBJ-001 (every household, and every person within each household), TEL-001, and PUR-001, under
three canonical principles that shape every section below:

| Principle | What it means for the domain |
|---|---|
| PRI-001 non-paternalism | The system never ranks, scores, recommends, or judges. Values are the member's own (REQ-111: no predefined values); calculations report facts (REQ-128, REQ-145, REQ-154, REQ-173). |
| PRI-002 member non-subordination | A member's condition is not reducible to the household's. There is no household administrator: no member has authority over another member's items or private records, and every household-level view is computed only over what the requesting member can see (REQ-106). |
| PRI-003 agency preservation with chosen delegation | Any delegation or automation is chosen and revocable by the member. This governs any future assistant or integration that acts for a member (section 7). |

---

## 1. Domain vocabulary

| Term | Meaning | Source |
|---|---|---|
| Household | The tenant: the unit a set of members belong to and share items within. | SUBJ-001; CP-019 mapping |
| Member | A person in a household; the only actor in domain operations. | SUBJ-001; REQ-101..110 |
| Item | Anything economic a member records. Every item has a non-empty owner set. Kinds: money item, value, account, debt, plan. | REQ-101; MEC-004; REQ-111; REQ-171; REQ-148 |
| Money item | Money in or out, in integer cents, with how often it happens (chosen by the member; no default) and an optional date. | REQ-129; REQ-136; REQ-157 |
| Value | Something a member values, as an item of kind value; the system provides none. | REQ-111; CAP-003; MEC-008 |
| Account | Checking, savings, other, or a retirement account (401(k), IRA); an item of its own kind, private by default. | REQ-171; REQ-149 |
| Debt | Card, HELOC, loan, or other; an item of its own kind, private by default. | REQ-171 |
| Reading | A dated balance for an account; amount owed, rate, and minimum payment for a debt. | REQ-131; MEC-017 |
| Plan | A member's private set of steps (switch items off from a month; add planned items); may be proposed as a shared plan. | REQ-142; REQ-148; MEC-019; MEC-020 |
| Owner set | The members who own an item. Changes need the consent of every current owner; any owner may remove only themselves while another remains. | REQ-101; REQ-107 |
| Grant | Read access to an item for a member who is not an owner. | REQ-103; REQ-167 |
| Proposal | A pending change to an owner set, a grant, or joining a value or shared plan, awaiting consent; can be withdrawn. | REQ-103; REQ-107; REQ-115; REQ-125; REQ-148; MEC-016 |
| Consent | A member's agreement to a proposal; joining a value or shared plan also needs the joiner's own consent. | REQ-115; REQ-148 |
| Ledger | The append-only record of each item's ownership, grant, and reading events, readable by its current owners. | REQ-105; REQ-170; MEC-003 |
| Link | A member's private association of a money item with a value. | REQ-168; MEC-009 |
| Mark | A member's private note that an item depends on a job (an income item). | REQ-144 |
| Attachment | A member's private statement of which cash account a money item goes through. | REQ-160; MEC-023 |
| Goal | A member's private emergency-fund goal (months of money out) or set-aside rate for a value's money in. | REQ-146; REQ-147 |
| Retirement assumptions | A member's private birth year, retirement age, return, contributions, and income target. | REQ-150; MEC-021 |
| Deletion record | A content-free record, private to the deleter, that they deleted an item. | REQ-108; REQ-121 |
| Portable record | The versioned export of what a member owns, and bringing it into a household. | REQ-155..159; REQ-164; REQ-169; CAP-009 |
| Leaving | A member who owns nothing leaving the household. | REQ-110; CAP-002; MEC-007 |

## 2. Domain contexts

Contexts follow capabilities, not tables or pages (ARCH-003 §8). Each is a set of public operations taking a trusted
scope (§7) and returning ARCH-003 §34's failure categories (§9). The domain rules beneath them are `core/`'s
modules, which already are plain functions with no processes or persistence (ARCH-003 §10).

| Context | Capabilities and mechanisms | Operations (from `core/` today) | Rules now in `core/` |
|---|---|---|---|
| **Households** | CAP-002 (leaving), MEC-007 | membership, leave | `Exit.leave` |
| **Items** (ownership, visibility, ledger) | CAP-001, CAP-005, MEC-002..005, MEC-016 | add item, propose owners, propose grant, consent, withdraw, relinquish, revoke grant, delete, read ledger, pending proposals | `Household`, `Ledger`, `View`, `Exit.delete` |
| **Values** | CAP-003, CAP-004, MEC-008..010 | add value, link, unlink, distribution | `Alignment` |
| **Balances** | CAP-010, MEC-017, MEC-023 | add account, add debt, add reading, readings, attach, payoff | `Balances`, `Attach`, `Projection.payoff` |
| **Cash flow** | CAP-011, MEC-018 | coming up, next 60 days, next 12 months, set-asides | `Schedule`, `Projection.project`, `Projection.set_asides` |
| **Planning** | CAP-007, CAP-012, CAP-013, MEC-019..021 | plans and steps, marks, shared plans, goals, emergency cover, retirement assumptions, retirement projection and sensitivity | `Plans`, `Projection.cover`, `Retirement` |
| **Portability** | CAP-009, MEC-012, MEC-022 | export, check a file, preview, bring in, refuse a repeat | `Exit.export`, `Import` |

Platform contexts (ARCH-003 §9), only those required: **Identity** (sign-in, sessions, revocation, recovery) and
**Tenancy** (the household scope) for the hosted form. Entitlements, Subscriptions, Notifications, and
Administration are not required by any ratified artifact and do not exist.

**ARCH-002's candidate names (REV-083 D1):**

| Candidate | Decision in this profile |
|---|---|
| Identity | Adopted as a platform context. |
| Households | Adopted as a domain context (membership and leaving). |
| Ledger | Not a context: the ledger is the Items context's record of its own events (REQ-105), not a separate capability. |
| Budgets | Excluded: no ratified Capability or Requirement defines budgets, and a budget that sets targets for a member would need checking against PRI-001. Open (section 12). |
| Institutions | Excluded: no ratified Capability or Requirement connects to banks, and any connection needs a Requirement and an egress-allowlist entry approved by ACT-001 (REQ-124). Open (section 12). |

## 3. Canonical domain state

One household's state is `core/`'s `Findependence.Household`: members, items (with owners, grants, attributes),
proposals, ledger, deletion records, readings, and each member's private records (links, plans, marks, goals with
retirement assumptions and attachments). It is canonical in one place per form:

| Form | Canonical store | Serialization of changes |
|---|---|---|
| Local-first | the encrypted vault file (section 10) | `Store` (one writer; detects outside changes) |
| Hosted | PostgreSQL through Ecto (ARCH-003 §12), laid out as in section 8 | Repo transactions and constraints (ARCH-003 §13) |

Nothing else is canonical: sessions, caches, pages, exports, and every calculation in section 6 are derived
(ARCH-003 §21). An export is a snapshot a member takes away, not a second source of truth (REQ-155).

## 4. Invariants

Every operation in every form keeps these. Each is a ratified Requirement; this profile only collects them.

- **Ownership:** every item has at least one owner (REQ-101); an owner set changes only with every current owner's consent, except that an owner may remove only themselves while another owner remains, and no one adds themselves (REQ-107); joining a value or shared plan also needs the joiner's consent (REQ-115, REQ-148).
- **Visibility:** a member can read an item only as an owner, an active grantee, or an agreed prospective owner of a value or shared plan (REQ-167); a grant needs every owner's consent and any owner may revoke one (REQ-103); an invisible item is reported as not found, so its existence is not revealed (ASM-014).
- **Aggregates:** every household-level view or total is computed only over items visible to the requesting member (REQ-106); losing visibility removes an item from that member's distribution without trace (REQ-114).
- **History:** ownership, grant, and reading events are appended, never changed, and readable by current owners (REQ-105, REQ-170).
- **Deletion and leaving:** only a sole owner deletes an item, which removes its grants, proposals, and ledger and leaves the deleter a content-free record (REQ-108); a member who owns nothing may leave, which removes their membership, grants, and pending proposals to them (REQ-110); the last participant of a shared value may delete it (REQ-116).
- **Money and schedules:** amounts are integer cents within the file's limits; how often a money item happens is the member's choice with no default; dates follow REQ-136 and REQ-137 (REQ-129, REQ-136, REQ-137, REQ-157).
- **Accounts and debts:** only owners add readings (REQ-131); who can read readings is fixed by REQ-132; accounts and debts are never money in or out and never linked (REQ-134); retirement accounts never count as cash (REQ-149).
- **Private records:** links, marks, attachments, plans, goals, retirement assumptions, and deletion records belong to one member and no one else can read them (REQ-121, REQ-142, REQ-144, REQ-146, REQ-147, REQ-150, REQ-160, REQ-168).
- **Once only:** a household-changing form sent twice changes the household at most once and says it was already saved (REQ-165).
- **Destructive changes:** deleting something that holds other records first shows what would go and asks to confirm (REQ-166).
- **Bringing in:** a file is untrusted and checked with the same rules as entry by hand; nothing is saved before the member confirms the preview; the same file is not brought in twice by the same member; bringing in changes nothing anyone else owns or sees (REQ-157, REQ-158, REQ-159).
- **No judgment:** no score, rank, recommendation, or judgment word on any page, calculation, or retirement result (PRI-001; REQ-128, REQ-154).

## 5. State transitions

| Subject | Transitions | Source |
|---|---|---|
| Proposal | pending → applied (every required consent given) · pending → withdrawn (by its proposer or any current owner) · pending → dropped (its item deleted or a party leaves) | REQ-107, REQ-115, REQ-125, REQ-108, REQ-110 |
| Item | created (by one member, owned by them) → owner set changed → deleted (sole owner) | REQ-101, REQ-107, REQ-108 |
| Grant | proposed → active → revoked, or dropped when the grantee leaves | REQ-103, REQ-110 |
| Member | member → left (owns nothing) | REQ-110 |
| Plan | private → proposed as shared → shared (as an item under the ownership rules) | REQ-142, REQ-148 |
| Brought-in file | checked → previewed → confirmed (entries created) or cancelled; a repeat is refused | REQ-156..159 |

## 6. Calculations

All are derived on request from canonical state, over what the requesting member can see, and are never stored
(ARCH-003 §21; `Projection` moduledoc: "Everything is computed on request").

| Calculation | Canonical inputs | Source |
|---|---|---|
| Value distribution | visible items, the member's links | REQ-128 |
| Per-month amounts | an item's amount and frequency | REQ-129, REQ-162 |
| Occurrences and dates | an item's date and interval | REQ-137 |
| Coming up (14 days), next 60 days, running balance, below-zero days | dated items that count for the member, accounts the projection starts from, attachments | REQ-161, REQ-173 |
| Next 12 months, with and without a plan | the member's items, plans, marks, accounts | REQ-162, REQ-143, REQ-144 |
| Set-asides for irregular money out | the member's items | REQ-140 |
| Debt payoff (minimum, extra, interest) | a debt's latest reading | REQ-145 |
| Emergency cover and progress | visible savings accounts, the member's money out, their goal | REQ-146 |
| Set-aside rate amount | money in linked to a value, the member's rate | REQ-147 |
| Retirement balance, income gap, duration, sensitivity | retirement accounts' latest readings, the member's assumptions | REQ-151, REQ-153, REQ-174 |

## 7. Domain-specific authorization

ARCH-003 §15 gives one decision path (actor, tenant, operation, resource, resource state, entitlement, policy). In
this domain:

- **Actor** is always a member of the scope's household. There are no roles: no member has more authority than
  another, and no household administrator exists (PRI-002).
- **Resource policy** is the ownership and visibility model (section 4): owner, active grantee, agreed prospective
  owner, or no access. Private records have exactly one reader, their member.
- **Operator:** in the hosted form the operator is not a domain actor. No operation runs as the operator, and no
  administrative surface reads item content, readings, or private records. Operator access to production is audited
  (REV-083 D3; section 9).
- **Delegation:** an assistant, integration, or automation may act for a member only through a delegation the member
  chose and can revoke (PRI-003), with the member as the actor, and only for the operations the delegation names.
  "Assistant intent ≠ authorization" (ARCH-003 §15) applies. No such delegation exists yet (section 12).
- **Enforcement point:** the public context operation. `core/`'s checks are rules, not a security boundary (ASM-013);
  the context builds the scope from trusted state and calls them. In both forms, a member's session can unseal only
  the keys sealed to that member (section 8), so the same rules also hold cryptographically.

## 8. Domain-specific privacy, and DEF-056's design

The hosted form keeps canonical state and decryption on the server (CP-018 B, REV-083 D3): the operator can read a
member's information while that member is signed in, and members are told this before they sign up (REV-079).
Inside a household, one member's private information stays unreadable to every other member, as in the local form.

### 8.1 Data classes

| Class | Who may read | Protection (both forms) | Source |
|---|---|---|---|
| Item content (attributes, kind-specific fields) | owners, grantees, agreed prospective owners | encrypted under a per-item key sealed to exactly those members | REQ-119, REQ-122 |
| Readings | as REQ-132 allows | each under its own key, sealed to those members | REQ-133 |
| Ledger entries | owners at the time of appending, then each new owner | encrypted and sealed to owners | REQ-170 |
| Private records (links, deletion records, plans, marks, goals, retirement assumptions, attachments) | the member | encrypted under a key only that member can unlock | REQ-121 |
| Member key material | the member | private key encrypted under a key derived from the member's passphrase (PBKDF2-HMAC-SHA256, at least 600,000 iterations, random 16-byte salt) | REQ-118 |
| Structure (household, members, item IDs, owner and grantee sets, proposal parties, versions, timestamps) | the system, to enforce the rules | plain, so constraints can hold (hosted) | REV-083 D5 |
| Exports | the member who took them | outside the system once downloaded; the file format carries no one else's private data | REQ-155, REQ-169 |

### 8.2 DEF-056: per-member encryption in PostgreSQL (REV-083 D5)

- **Rows:** item content, readings, ledger entry details, and private records are stored only as ciphertext produced
  by the application. Household, membership, item IDs, owner and grantee sets, proposal parties, versions, and
  timestamps are plain columns carrying foreign keys and constraints, so tenant integrity and the ownership rules
  have database backing (ARCH-003 §14). An item's kind stays encrypted, as REQ-122 keeps it out of the local file.
- **Keys:** as the local form does today (MEC-013, MEC-014). Each item, reading, and ledger entry has its own key,
  sealed to each member who may read it (REQ-119, REQ-133, REQ-170); a member's private key is wrapped by their
  passphrase-derived key (REQ-118); private records are encrypted under a key only the member unlocks (REQ-121).
- **Sessions:** the member's unwrapped keys exist only in server memory for their session and are discarded at
  sign-out or after 15 idle minutes, as REQ-123 does locally. They are never written to PostgreSQL, logs, telemetry,
  jobs, or PubSub messages.
- **Placement:** encryption and decryption happen inside the public context operations. `core/`'s rules see
  decrypted data; persistence sees ciphertext and structure. Oban jobs and PubSub messages carry IDs only, never
  content (ARCH-003 §17, §19, §30).
- **What stays visible to the operator and the database:** who is in which household, how many items each member
  owns or shares and with whom, when things change, and sizes. This is the metadata cost of CP-018 B with enforceable
  constraints, and is disclosed with it.
- **Cost:** the database cannot sum or search encrypted amounts; `core/` computes on request, as it does today.

DEF-056 is resolved when ACT-001 ratifies this profile.

### 8.3 Lifecycle (ARCH-003 §30)

| Class | Retention | Export | Deletion | Backups |
|---|---|---|---|---|
| Items, readings, ledger | while the item exists | by owners (REQ-169) | sole-owner deletion removes item, grants, proposals, ledger (REQ-108) | open: a hosted backup keeps ciphertext until it expires; retention and restore to be set with the operator decision (REV-079) |
| Private records | while the member belongs | the member's own (REQ-155, REQ-169) | links, plans, marks, and goals are removed on leaving, as `core/`'s `Exit.leave` does (REQ-110 names only membership, grants, and proposals); deletion records stay private to the deleter (REQ-108) | as above |
| Membership | until the member leaves | — | REQ-110 | as above |
| Logs and telemetry | short, operational only | never | expire | contain no names, amounts, or content (REQ-177, proposed; ARCH-003 §33) |

## 9. Domain-specific audit

- **Domain history:** the ledger is the domain's audit of ownership, grants, and readings, readable by current owners
  (REQ-105, REQ-170); deletion records are the deleter's own (REQ-108).
- **Platform audit (ARCH-003 §33), content-free:** sign-in and failed sign-in, session revocation, export, bring-in,
  leaving, deletion, and operator access to production (REV-083 D3). Each record names the actor, household,
  operation, resource ID, time, channel, and outcome, and never a name, amount, or other content.

## 10. The local-first exception (REV-083 D2)

ARCH-003 describes a hosted service. The local-first form is kept for the pilot under this recorded exception:

- **Canonical state** is the encrypted vault file on one household device, not PostgreSQL.
- **Serialization** is `Store`, a single process writing the file; it exists because of a runtime property ARCH-003
  §10 accepts (one writer, outside changes detected), not as a service layer.
- **Identity and sessions** are member and passphrase unlock on the device, with `Sessions` holding unlocked keys and
  sweeping idle ones (REQ-123).
- **Transport** is the loopback-only Plug interface (REQ-123), with an empty egress allowlist (REQ-124).
- **Everything else is shared:** the same public context operations, `core/`'s rules, the vocabulary, invariants,
  authorization, and privacy model in this profile. Only persistence coordination differs per form.

The exception ends with the local form's retirement, which ACT-001 decides after the pilot (REV-083 D2).

## 11. Domain-specific assurance evidence

| Requirement area | Evidence |
|---|---|
| Invariants (section 4) | each specified Requirement's acceptance criteria and the tests VV-002 maps to them, run on both forms' contexts |
| Calculations (section 6) | `core/`'s unit and property tests; the same results through each form's contexts |
| Authorization (section 7) | positive and negative tests per operation: owner, grantee, prospective owner, other member, other household |
| Privacy (section 8) | stored-data inspection: no content in plain columns, files, logs, jobs, or PubSub messages; a member's session cannot unseal another member's private record |
| Convergence (ARCH-003 §5, §35) | adapter-to-context tests once a second transport exists; a dependency test that the web layer calls only contexts (CP-020 U3) |
| Egress (REQ-124) | the runtime egress test DEF-057 records as missing |
| Audit (section 9) | tests that each audited operation writes one content-free record |

## 12. Open, not decided here

- **Budgets and bank connections (Institutions):** no ratified Capability or Requirement; each would need one, a PRI-001 check (budgets), and ACT-001's approval of egress destinations (bank data, REQ-124).
- **Assistants, mobile, notifications:** ARCH-003 §23–26 describe how they attach; none has a Requirement, and each needs a delegation model under PRI-003 (section 7).
- **Proposed, not ratified:** CAP-006 (low-effort upkeep), CAP-008 (agreed shares of joint items), REQ-163 (amount history), REQ-175..179 (interface hardening). This profile does not rely on them.
- **Hosted retention and backups:** set with the operator decision (REV-079 open decision 5).
- **Key derivation for the hosted form:** REQ-118 fixes PBKDF2-HMAC-SHA256; whether the hosted form should move to a memory-hard function is a Requirement change for ACT-001, not a profile decision.
