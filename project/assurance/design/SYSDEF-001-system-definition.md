# SYSDEF-001: Findependence system definition

**What this is:** one document that defines the whole system as it stands at v0.8.5-alpha (main `81c1bad`; records at `f30a877`, 2026-10-03), assembled
from the project's canonical records. It is a **derived** artifact: every statement cites the record it comes from,
and where this document and a record differ, the record prevails (CONSTITUTION, canonical-source precedence). It
changes nothing that is ratified.
**For:** anyone who needs the whole picture at once: ACT-001, the independent security reviewer (GATE-016), the
ethics body, a professional checking the legal context, and future contributors.
**Kept current by:** regenerating the inventories (section 14) from the records at each release; a mismatch
between this document and a record is a defect in this document.

---

## 1. Identity and justification

| Level | Statement | Record | State |
|---|---|---|---|
| Subject | Every household, and every person within each household. | SUBJ-001 | canonical |
| Telos | Every household, and everyone in it, free to pursue the life they value, not held back by money. | TEL-001 | canonical |
| Purpose | Increase the effective capacity of households and their members to deliberately shape their economic lives in service of the lives they value. | PUR-001 | canonical |
| System | Findependence: a household finance system in two deployment forms. (1) Local-first: run on one household device, each member's information encrypted separately at rest, and a browser interface served only to that device; its first deployment context is STUDY-001 in Sumner, WA. (2) Hosted: a service run by an operator, in which the server decrypts a member's information while they are signed in, so members trust the operator with their finances (CP-018 B); members are told this before they sign up. It is a research prototype, not a security product (ASM-013, DEF-026); the hosted form is offered to no one until its own security, legal, and ethics reviews pass. | SYS-001 | specified |

**Principles** (canonical; every design decision is checked against them):

| | Principle | Meaning in practice |
|---|---|---|
| PRI-001 | **Non-paternalism.** The Subject, not the System, defines which lives are valued; the System does not rank or optimize toward system-chosen valued lives. | No scores, ratings, targets, or advice; members' values in their own words (CAP-003); judgment words are banned from the interface (glossary checks). |
| PRI-002 | **Member non-subordination.** Household-level gains don't justify reducing any member's agency or condition; a member's condition isn't reducible to a household aggregate. | Every member's information is theirs; deny-by-default visibility; aggregates only over what the requester can see (REQ-106); a member can leave alone (CAP-002). |
| PRI-003 | **Agency preservation with chosen delegation.** The System augments rather than supplants decision-making; any delegation or automation is chosen and revocable. | Nothing happens without the member's action; consent can be withdrawn (REQ-125); the hosted form's trust in its operator is disclosed and chosen (REQ-180). |

**Who the system is for, and who it isn't:** the Subject is universal (ASM-007); the users are households that
choose to use it. A household is an economic unit of one or more people sharing some part of their economic life,
regardless of housing (ASM-001); a person may belong to more than one household (ASM-002), though each hosted
account belongs to one household at a time (REQ-185).

## 2. Scope

**In scope:** recording a household's money in and out, values, accounts and debts with balances, dated cash flow,
twelve-month projections and plans, goals, retirement projections, consent-governed sharing between members, and
carrying one's own record out of a household and into another.

**Out of scope, by decision:**

| Excluded | Record |
|---|---|
| Connecting to banks or importing transactions automatically | CTX-001 (local_first, hosted: "no bank connectivity") |
| Financial advice, product suggestions, investment recommendations, targets | CTX-001 ("no advice"); PRI-001; REQ-154 |
| Moving money: payments, transfers, bills | not part of any Capability |
| Payment-card data | not collected |
| Being a security product | SYS-001; DEF-026 |
| Use by any real household or with real data before the pilot's gates | REV-034; GATE-016 |

## 3. People and roles

| Role | Who | What they do | Record |
|---|---|---|---|
| Initiating project authority | ACT-001 (William Drake) | Ratifies the foundation, accepts Requirements and changes, approves releases | governance/actors.yaml; GOVERNANCE.md |
| AI implementation agent | ACT-002 (Claude) | Proposes, implements within approved WorkItems, runs checks; no authority of its own | AGENTS.md; GOVERNANCE.md |
| Member | a person in a household | Owns and shares their information, agrees or not, leaves | CAP-001..CAP-013 |
| Household | one or more members | The unit whose economic life the system serves | ASM-001 |
| Operator (hosted only) | whoever runs the hosted service | Trusted while members are signed in; access audited; bound by OPS-001 | REV-111; REQ-180, REQ-191, REQ-193..196 |
| Tester (alpha) | people ACT-001 invites | Use the local form with made-up data only | manifest releases.alpha; app/ALPHA.md |
| Study participant (pilot) | 3 to 5 households in or near Sumner, WA | Use the local form for 4 weeks, observed | STUDY-001 (approved, not enrolled) |
| Independent security reviewer | not yet engaged | Reviews the cryptography, the self-review, ASSESS-001, ASSESS-002, and DESIGN-002, at tag `review-3` | GATE-016 1_security_review; DEF-026 |
| Ethics body | not yet chosen | Reviews the study | GATE-016 2_ethics_review |
| Professional (legal) | not yet chosen | Checks the Washington and US notes, including whether GLBA applies to the hosted form | GATE-016 3_professional_check |

## 4. Outcomes the system serves

Nine Outcomes give the Purpose's breadth (OBA-001). Two were chosen as sentinels for the first build (SYN-001):
**OUT-005 member standing** (first) and **OUT-002 alignment** (second).

| Outcome | Statement | How the system serves it now |
|---|---|---|
| OUT-001 legibility | The household and each member can understand their current and projected situation well enough to decide | CAP-007, CAP-010, CAP-011, CAP-012 |
| OUT-002 alignment | Economic activity serves what the household and each member value, as they define it | CAP-003..CAP-005 (sentinel) |
| OUT-003 means | Obtaining what they're entitled to on fair terms | CAP-014 accepted, not built (REV-117); STUDY-001 Q7 |
| OUT-004 coordination | Making and carrying out shared decisions fairly, without depending on one member | Consent rules (CAP-001), shared values and plans (CAP-005, FUN-018); tension with OUT-005 open (DEF-015) |
| OUT-005 member standing | Each member has independent, protected standing: their own information, resources, voice, and ability to leave safely | CAP-001, CAP-002, CAP-009 (sentinel); signed agreements and the 72-hour cooling-off (REQ-201..REQ-203) |
| OUT-006 resilience | Absorbing and recovering from shocks and exploitation | CAP-013 goals (emergency fund); CAP-010 debts |
| OUT-007 optionality | Keeping and expanding future options, avoiding lock-in | CAP-009 portable record; CAP-012 retirement |
| OUT-008 continuity | Coherence through joining, leaving, separation, death, incapacity | CAP-002 exit; joining after setup designed (CP-009), local form not built (ASM-022) |
| OUT-009 bounded burden | Managing money doesn't crowd out life | Design aim; measured by STUDY-001 Q5; CAP-006 (low-effort upkeep) proposed |

## 5. Capabilities, functions, and mechanisms

| Capability | State | What a member can do | Functions | Mechanisms |
|---|---|---|---|---|
| CAP-001 consent-governed visibility | specified | Hold information that is theirs and decide who sees it; joint items visible to all holders | FUN-001..FUN-004 | MEC-002 deny-by-default visibility; MEC-003 per-item ledger; MEC-004 owner sets |
| CAP-002 independent exit | specified | Take their record and leave without anyone's cooperation | FUN-005..FUN-008 | MEC-004, MEC-005 sole-owner deletion, MEC-007 unilateral departure, MEC-012 owner-scoped export with own links |
| CAP-003 value articulation | specified | Record what they value in their own words, private by default | FUN-009 | MEC-008 values as owned items |
| CAP-004 activity–value linking | specified | Relate items to their values and see the distribution, without evaluation | FUN-010, FUN-011 | MEC-009 private links; MEC-010 visibility-scoped distribution |
| CAP-005 shared commitments by consent | specified | Share values that exist only while every participant consents; anyone can withdraw | FUN-012, FUN-013 | MEC-011 shared value as consented joint value; MEC-016 proposal withdrawal |
| CAP-006 low-effort upkeep | **proposed** | Bulk and rule-based linking, ignorable without penalty | — | — |
| CAP-007 projection and plans | specified | See money over the next twelve months with debt interest; compare private plans | FUN-016, FUN-018 | MEC-019 private plans and projection; MEC-020 shared plans by consent |
| CAP-008 agreed shares of joint items | **proposed** | Agree how a joint item's amount is shared | — | — |
| CAP-009 portable record | specified | Bring an export into a new household | FUN-020 | MEC-022 strict owner import |
| CAP-010 balances and debts | specified | Record accounts and debts with balances, rates, minimum payments; private by default | FUN-014 | MEC-017 balances as readings |
| CAP-011 dated cash flow | specified | See what's coming up, sixty days ahead with a running balance and any day below zero, and what to set aside | FUN-015 | MEC-018 anchored schedules; MEC-023 private account attachments |
| CAP-012 retirement projection | specified | Project retirement accounts to a chosen age under their own assumptions, against their own target, with no suggestions | FUN-019 | MEC-021 private retirement assumptions |
| CAP-013 goals the household sets | specified | Set goals in their own terms and see progress | FUN-017 | MEC-019 |
| CAP-014 claims on the member's terms | specified, not built | Keep track of something they are owed or could claim, privately, with a status they set | — | — |

**Cryptographic and interface mechanisms** (local form): MEC-013 per-member key material, MEC-014 sealed item
envelopes, MEC-015 loopback browser interface; extended by REQ-192 (signed records, verified seals).

## 6. Deployment forms and architecture

### 6.1 Code structure

| Layer | Directory | What it holds | Elements |
|---|---|---|---|
| Domain core | core/ | The household rules as pure functions: ownership, grants, consent, proposals, ledger, visibility, exit, alignment, balances and schedules, projections and plans, retirement, import | IE-101..IE-110 |
| Shared application layer | shared/ | Used by both forms: the trusted scope, contexts, the envelope (sealing, opening, signing, seal commitments, integrity checks), cryptography wrappers, safe decoding, words and messages | IE-206 (with IE-201's crypto) |
| Local-first form | app/ | Vault file, member sessions, store, loopback web interface, setup/serve/demo tasks | IE-202..IE-205 |
| Hosted form | hosted/ | Accounts, tenancy, PostgreSQL storage of the vault's shape, server-rendered pages, operator audit, release commands, operating controls | IE-207..IE-211 |
| Governance tooling | automation/ri01, scripts/ | `check` and `trace` engines | IE-001..IE-004 |

Stack: Elixir 1.20.4, Erlang/OTP 29 (OpenSSL 3.5 through `:crypto`), Plug and Bandit (local), Phoenix 1.8 with
server-rendered HEEx and Petal Components (hosted), PostgreSQL 17 (hosted). No third-party cryptography library.

### 6.2 Local-first form (what testers use)

- **Runs on one household device**, served on 127.0.0.1 only, Host header checked exactly, CSRF on every form,
  `SameSite=Strict` encrypted session cookie, no JavaScript, no remote resources, strict CSP (MEC-015, REQ-123).
- **One encrypted vault file** (mode 0600, written atomically) holds the household. One member is unlocked at a time;
  sessions lock after 15 idle minutes (REQ-123; CP-016 proposes a change) (ASM-022).
- **Membership is fixed at setup**; members can leave but not join (ASM-022; CP-009 designs joining).
- **No outbound connections** (REQ-124).
- Decision basis: CP-006 option B (one shared device, each member's information encrypted separately); its limit for
  members who live elsewhere is open (DEF-030).

### 6.3 Hosted form (complete, not in service)

- **Server-rendered HTML with progressive enhancement; the web server is the backend-for-frontend**: sessions and
  keys are held only in server memory, the browser holds an HttpOnly cookie with a random token (REV-111; ARCH-004
  section 6).
- **Trusted operator:** while a member is signed in the server holds their unwrapped key, so the operator could read
  their information; members are told before signing up (REQ-180; CP-018 B; ASSESS-001 FND-22 accepted).
- **Accounts** are identified by an account number shown once at sign-up (no email address kept), protected by a
  passphrase (under a server-held pepper, common passphrases refused, REQ-197) and a replaceable recovery key
  (REQ-181, REQ-184; CP-026).
- **Households** are created by a member and joined with one-time invitation codes (REQ-185); all operations act
  within the session's household (REQ-186).
- **Storage:** each household's records as one AES-256-GCM block under a server key, display names included
  (REQ-200), with a code over them checked at every read and a change counter kept outside the database, so a
  household changed or restored other than through the service is refused (REQ-198; WI-085, WI-086); request
  identifiers that don't reveal counts (REQ-199); separate owner and runtime database roles, verified TLS,
  append-only audit (WI-081; OPS-001).
- **Same capabilities and rules as the local form** through the shared contexts (REQ-188).
- **Operating controls** (OPS-001; REQ-193..REQ-196): remote console off by default and audited; no crash or core
  dumps; preflight check blocking start; readiness tied to the database; hardened service unit; DEPLOY.md.
- Clients for desktop and mobile: the same pages as an installable web app or app-store wrappers, online only
  (ARCH-004 section 6).
- Architectural reference: ARCH-003 (final target), with ARCH-001 as the technology and security profile and
  DP-001 as the domain profile (REV-082, REV-083, REV-085).

## 7. Domain model

| Concept | Definition | Record |
|---|---|---|
| Household | Members fixed at creation (local) or joined by code (hosted) | ASM-022; REQ-185 |
| Member | A person in the household; their keys, personal record, and display name | MEC-013 |
| Item | Anything economic, with a non-empty owner set and grantees; immutable once created | REQ-101; ASM-021 |
| Item kinds | money in or out (amount, how often, an optional date); value; account (checking, savings, other, 401(k), IRA); debt (card, HELOC, loan, other); shared plan | REQ-111, REQ-129, REQ-171, REQ-149, MEC-020 |
| Owners | Change only with all current owners' consent and every new owner's own, except an owner may remove only themselves while another remains | REQ-107, REQ-115 |
| Grantees | See an item without owning it; only owners grant (with all owners' consent on joint items) and revoke | REQ-103, REQ-167 |
| Proposal (request) | A pending owner change, grant, or (with the cooling-off on) a sole owner's deletion. Each agreement is signed by the member giving it and counts only if it verifies; once every current owner has agreed, a widening change or deletion waits 72 hours, computed from the signed times; withdrawable, and cancellable alone by whoever's agreement it rests on | REQ-103, REQ-115, REQ-125, REQ-201..REQ-203 |
| Ledger | Each item's append-only history of ownership and visibility changes, readable by its owners | REQ-105, REQ-170 |
| Reading | A dated balance (and, for debts, rate and minimum payment) added to an account or debt; append-only | REQ-131..REQ-133 |
| Personal record | The member's own links, plans, job marks, goals, retirement assumptions, account attachments, deletion records; private and encrypted | REQ-121, MEC-019, MEC-021, MEC-023 |
| Export | A versioned JSON file (findependence-export, version 2) of what the member owns and their own records | REQ-155, REQ-169, MEC-022 |

**Invariants the rules enforce:** an item always has an owner; visibility is evaluated at every read, including
aggregates; nobody adds themselves as an owner; a member who owns nothing can always leave; a joint owner can always
stop owning; a sole owner can always delete; leaving withdraws the leaver's agreements (WI-079) and is never delayed; only an agreement its member signed counts
(REQ-203); nothing a member can't see contributes to anything they're shown (REQ-106).

## 8. Behaviour

| Area | Behaviour | Requirements |
|---|---|---|
| Visibility | Deny by default; owners and grantees only; a hidden item answers as not found | REQ-106, REQ-167; ASM-014 |
| Consent | Grants and owner changes need every current owner, and a new owner of any item also consents; each agreement is signed by its member; proposals can be withdrawn | REQ-103, REQ-107, REQ-115, REQ-125, REQ-148, REQ-203 |
| Cooling-off | Sharing, giving away, and deleting take effect 72 hours after every current owner has agreed; nothing is shown or sealed before; the member whose agreement it rests on cancels alone; revoking, stopping owning, exporting, and leaving are immediate | REQ-201, REQ-202 |
| Exit | Relinquish, delete if sole owner, export, leave, each alone | REQ-107, REQ-108, REQ-110, REQ-169 |
| Values and alignment | Values in the member's own words; private links; distribution per month by value, over what they can see, without evaluation | REQ-111, REQ-114, REQ-128, REQ-168 |
| Balances | Accounts and debts with readings; their own pages; debt facts at the latest reading | REQ-131..REQ-134, REQ-145, REQ-171, REQ-172 |
| Cash flow | Dated items; next fourteen days on home; sixty days with a running balance and below-zero days; set-aside for less-than-monthly costs; which account an item goes through | REQ-136, REQ-137, REQ-140, REQ-160, REQ-161, REQ-173 |
| Projection and plans | Twelve months with debt interest; private plans side by side; job marks; shared plans by consent | REQ-142..REQ-144, REQ-148, REQ-162 |
| Goals | Emergency fund in months; set-aside rate for business income | REQ-146, REQ-147 |
| Retirement | Accounts, assumptions, year-by-year projection, sensitivity, target income; no suggestions | REQ-149..REQ-151, REQ-153, REQ-154, REQ-174 |
| Portability | Versioned export; bring-in into another household as the member's own, previewed first, untrusted file (1 MB, strict checks), not twice | REQ-155..REQ-159, REQ-164 |
| Forms | A form sent twice changes the household once; deleting something with history is confirmed first | REQ-165, REQ-166 |

## 9. Data and privacy

| Data | Where | Protection | Who can read it | Leaves the system |
|---|---|---|---|---|
| Item content (names, amounts, schedules) | vault file / item rows | AES-256-GCM per item, key sealed to each reader; signed by its author | owners and grantees | only in that member's export |
| History entries | vault / ledger rows | encrypted per entry, sealed to owners, signed | owners | export (owned items) |
| Balance readings | vault / reading rows | encrypted per reading, sealed per REQ-132, signed | latest to readers, all to owners | export |
| Personal record | vault / personal rows | encrypted under the member's personal key | that member only | export |
| Access structure: member ids, owner and grantee lists, proposals, item ids | vault file / the hosted household block | local: **plaintext** (ASM-020); agreements signed (REQ-203), the rest not authenticated (DEF-028). Hosted: encrypted and coded under server keys (REQ-198, REQ-200) | local: anyone with the file; hosted: the operator | — |
| Keys | inside each member's encrypted secret (local) or wrapped account rows (hosted) | PBKDF2-HMAC-SHA256 600,000 iterations; recovery key (hosted) | the member; the hosted server's memory while signed in | never |
| Account number (hosted) | keyed hash, and encrypted for the member | HMAC-SHA256; encryption under a key from the member's private key | the member while signed in | never |
| Display names (hosted) | membership rows | encrypted under a server key (REQ-200) | household members, operator | — |
| Audit records (hosted) | audit table | append-only; content-free | operator | shipped off-host for review (OPS-001) |
| Logs | console / server log | parameters filtered; crash details withheld (local); no content (REQ-191; REQ-177 proposed) | operator / device user | — |

**Retention and deletion:** deleting an item removes it and its history, keeping a content-free deletion record
for the deleter (REQ-108); leaving removes the member's grants and personal record (REQ-110); deleting a hosted
account removes its key material and membership, keeping content-free audit records (REQ-189); deletion is not
secure erasure on disk (SELF-REVIEW F-08); hosted backups keep data until their retention ends (OPS-001 B3).

**What the local form protects, and from whom** (THREAT-MODEL): members' contents from each other and from someone
who copies the file (G1); tampering is meant to give no access (G2) and to be visible (G3); a malicious website
can't reach the interface (G4); nothing in plaintext on disk except by the member's choice (G5). **Not protected:**
metadata (ASM-020); integrity and availability against a member who edits the file: removals and rollback (non-goals;
DEF-028; forged agreements are refused since v0.8.5, REQ-203); coercion, which the cooling-off gives a private
chance to undo but can't detect (DEF-016; REQ-201).

## 10. Security

| Topic | State | Records |
|---|---|---|
| Cryptographic design | AES-256-GCM, X25519 + HKDF-SHA256 seals, PBKDF2 600k, Ed25519 signatures derived from each member's key on records and on agreements, seal commitments, pinned keys; all from OTP `:crypto` | DESIGN.md (with WI-079, WI-080, WI-088/WI-090 sections); MEC-013, MEC-014; REQ-118..REQ-122, REQ-133, REQ-192, REQ-203 |
| Implementation assessment | ASSESS-001: 22 findings, all mitigated or decided (WI-079..WI-081, CP-024). ASSESS-002 (hosted): 8 findings, mitigated by WI-085 and WI-086 except the accepted operator path. **Neither independent** | security-review/ASSESS-001*, ASSESS-002* |
| Independent review | **not done; blocks any real household** | DEF-026; GATE-016 |
| Remaining structural weakness | Unauthenticated access state: removals, an unsigned request and proposer, rollback (local); the operator's same abilities (hosted). Forged agreements closed in both forms by WI-090; the full fix chosen (DESIGN-002), not built | DEF-028, DEF-077; CP-027, CP-031; DESIGN-002 |
| Web interface (local) | loopback, Host check, CSRF, SameSite=Strict, CSP, no JavaScript, param shapes, body limits | REQ-123; WI-079 |
| Hosted controls | rate limits with device cookies, sign-up limit, account numbers, session lifetime, recovery-key replacement, passphrase pepper, records' code and change counter, encrypted household block, roles, TLS, audit, console off, no dumps, preflight | REQ-180..REQ-200; OPS-001 |
| Operator access (hosted) | trusted and disclosed; audited; procedures owned by ACT-001 | REV-111; REQ-180; OPS-001 A2, F1..F5 |
| Supply chain | Hex lockfile hashes, hex.audit in the gate, Tailwind pinned to published digests, container images by digest | WI-081; REQ-179 (proposed) |

## 11. Interfaces

| Interface | Form | Description | Records |
|---|---|---|---|
| Browser pages | local | Home, items, values, accounts and debts, next sixty days, twelve months ahead, plans, goals, retirement, export, bring-in, leave checklist, unlock/lock | REQ-123, REQ-161.. |
| Browser pages | hosted | The same pages, plus sign-up, sign-in, recovery, passphrase, recovery key, household and invitations, account deletion | REQ-180..REQ-189 |
| Command line (local) | local | `mix findependence.setup`, `serve`, `demo` | app/ALPHA.md |
| Release commands (hosted) | hosted | migrate, rollback, preflight report, operator-access listing; health endpoints | IE-211; DEPLOY.md |
| Export file | both | findependence-export version 2 (JSON) | REQ-155; MEC-022 |
| Network egress | both | local: none; hosted: its database only | REQ-124 |

## 12. Quality attributes

| Attribute | Commitment | Evidence |
|---|---|---|
| Accessibility | No axe violations or needs-review at 1200 and 390 px in both themes; Tab walk in DOM order with visible focus (contrast ≥ 3:1, measured 14.55:1 or more); forced colours; table semantics on phones; geometry checks | REPRO-RUN-026; UX contract (ROADMAP-ALPHA section 3) |
| Wording | Glossary terms only; no judgment words | glossary tests |
| Performance | Server time ≤ 50 ms at 200 items (46.6 ms at v0.8.5); home ≤ 7,812 px at 50 items on a phone (6,968 px) | REPRO-RUN-026 |
| Reliability | Atomic writes; one writer at a time; changes refused if another process wrote first; an unreadable file keeps the last copy | SELF-REVIEW F-16; WI-079 |
| Reproducibility | Every release rebuilt from a clean checkout with each suite run twice | REPRO-RUN-001..026 |
| Availability | Not a goal for the local form; no backup (CP-010 A) | THREAT-MODEL T7 |

## 13. Constraints and governance

- **Development discipline:** governed refinement from Idea to Runtime, traceable both ways (CONSTITUTION; CON-004);
  deterministic checks (`scripts/check`, `scripts/trace`) with no side effects (CON-001..CON-003); authority for
  transitions and acceptance per the authority policy (CON-005); raw output isn't Evidence until qualified, and a
  Claim isn't supported until assessed (CON-006).
- **Who decides:** ACT-001 ratifies foundations, Requirements, changes, and releases; ACT-002 proposes and implements
  within approved WorkItems (GOVERNANCE.md; AGENTS.md).
- **Release stages:** alpha (made-up data, invited testers; current), pilot (first real households; requires GATE-016:
  security review, ethics review, professional check) (manifest; REV-034).

## 14. Inventories (regenerate at each release)

| Kind | Count | Notes |
|---|---|---|
| Outcomes | 9 | all specified |
| Capabilities | 14 | 12 specified (CAP-014 not yet built), 2 proposed (CAP-006, CAP-008) |
| Functions | 20 | FUN-001..FUN-020 |
| Mechanisms | 23 | MEC-001, MEC-006 superseded |
| Requirements | 119 | 98 specified, **every one satisfied by an implementation element**; 6 proposed (REQ-163 editing items, REQ-175..REQ-179 interface rules from ARCH-001); 15 superseded |
| Implementation elements | 27 | IE-001..004 tooling, IE-101..110 core, IE-201..206 local and shared (verified, GATE-044 for the latest), IE-207..213 hosted (implemented, awaiting a gate at first release) |
| Assumptions | 20 | ASM-001..ASM-022 (two numbers unused) |
| Open Defeaters | 12 | section 17 |

## 15. Verification and assurance status

- **Current Claim:** CLM-043, supported (ASMT-034): at the v0.8.5-alpha candidate (0a45c33), the local form satisfies
  CLM-042's Requirements and REQ-203, each with a passing test. CLM-039 (v0.8.1) is weakened for REQ-133 (ASMT-030).
- **Gate:** GATE-044 verified the elements changed for v0.8.5 (IE-101, IE-202, IE-205, IE-206).
- **Tests at v0.8.5:** core 213, shared 9, app 650, hosted 505, tooling 69; e2e 55 of 55 without the wait and 10 of
  10 with the real 72 hours (REPRO-RUN-026).
- **What is not established:** any Claim above implementation level (the study tests those: CLM-012, CLM-014);
  security (DEF-026); the hosted form's Requirements as a Claim (no hosted Claim yet).

## 16. Release and deployment status

| Item | State |
|---|---|
| Local form | v0.8.5-alpha released (tag at 81c1bad, pushed 2026-10-03), testers only, made-up data; v0.8.4 files open, and their waiting requests ask again |
| Hosted form | complete on main, **not in service**; needs its security, legal, and ethics reviews, a deploying WorkItem, and the operating procedures |
| Pilot (STUDY-001) | approved protocol; enrollment blocked by GATE-016 |

## 17. Open issues

**Open Defeaters:**

| Defeater | Severity | Issue |
|---|---|---|
| DEF-026 | blocking | No independent review of the cryptography and key handling |
| DEF-028 | high | Unauthenticated access state in the local vault (removals, requests, rollback; agreements signed since WI-090); DESIGN-002 chosen, not built |
| DEF-077 | material | The same in the hosted form, for the operator; whoever can write only the database is stopped (REQ-198, REQ-200) |
| DEF-081 | material | The study consent form understates what someone who can edit the file can do |
| DEF-015 | material | Coordination (OUT-004) versus member standing (OUT-005): all-owner consent can block joint action |
| DEF-016 | material | Coerced consent can't be detected; the cooling-off (REQ-201, REQ-202) gives a private chance to undo |
| DEF-017 | material | The Outcome set and sentinel scores are one agent's judgment |
| DEF-022 | material | Values adapted to deprivation can look well aligned |
| DEF-030 | material | One shared device leaves members who live away unable to use it |
| DEF-004 | material | Where insufficient means is the binding constraint, more capacity may contribute little |
| DEF-007 | minor | Purely subjective valuation can understate how far deprived households are held back |
| DEF-023 | minor | Private links let members interpret a shared expense differently without knowing |

**Open decisions:** GATE-016's three reviews; CP-016 (idle lock length, proposed); the proposed Requirements
(REQ-163, REQ-175..REQ-179) and Capabilities (CAP-006, CAP-008); building DESIGN-002 after review; the hosted form's
deploying WorkItem and first release; the long-term future of the local form after the pilot (REV-083, D2 option a).

## 18. Assumptions (summary)

Foundational: ASM-001..ASM-009 (what a household is; that the Subject values, not the System; what the Telos and
Purpose mean; ACT-001's authority). Design: ASM-012 (whose values prevail is open), ASM-013 (the core enforces rules
at its API, not as a security boundary), ASM-014..ASM-018 (visibility and consent choices), ASM-019 (sorted output for
reproducibility), ASM-020 (plaintext metadata), ASM-021 (immutable items), ASM-022 (fixed membership, one session at a
time). The full text is in project/assurance/assumptions.yaml.

## 19. Glossary

| Term | Meaning here |
|---|---|
| Item | Anything economic a member records: money in or out, a value, an account, a debt, a shared plan |
| Owner / grantee | Who holds an item / who may see it without owning it |
| Proposal / agreement | A pending change of owners, a grant, or a deletion / a member's signed consent to it |
| Cooling-off | The 72 hours a widening change or deletion waits once every owner has agreed |
| Reading | A dated balance added to an account or debt |
| Value | Something a member cares about, in their own words |
| Link | A member's private connection between an item and a value |
| Vault | The local form's encrypted household file |
| Seal | An item or entry key encrypted to one reader |
| Operator | Whoever runs the hosted service |
| Local-first / hosted | The two deployment forms (SYS-001) |

## 20. Sources

Canonical: SUBJ-001, TEL-001, PUR-001, PRI-001..003 (semantic/); SYS-001, CTX-001, OUT-001..009, CAP-001..013,
FUN-001..020, MEC-001..023, CON-001..006 (semantic/); Requirements (realization/requirements*.yaml); elements
(realization/implementation*.yaml); assumptions, Defeaters, Claims, Assessments, Evidence (assurance/); gates and
WorkItems (lifecycle/); reviews (governance/); changes (change/). Design: ARCH-001, ARCH-003, ARCH-004, DP-001,
DESIGN-002, OPS-001 (assurance/design/, security-review/). Security: security-review/ (README, THREAT-MODEL, DESIGN,
SELF-REVIEW, EVIDENCE, ASSESS-001, ASSESS-002). Plans: STUDY-001, ROADMAP-ALPHA (assurance/plans/).
