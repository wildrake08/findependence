# ASSESS-002: resource, delegation, and operator-isolation assessment of the hosted form

**Assessed:** main at 5592d94 (after WI-079..WI-084; the local form as released in v0.8.2-alpha), 2026-10-01, by
ACT-002. **Not independent:** the same AI system family wrote the code. This adds evidence for GATE-016
`1_security_review`; it does not discharge it or DEF-026.

**Brief:** ACT-001's assessment brief of 2026-10-01: a canonical model of resources, information domains,
principals, relationships, delegations and revocation; the invariants ISO, DEL, REV, DER, OI, OE, EM, PC, DI, DM,
SC, MM and SD; the user-agency properties UA-1..UA-5; the trusted computing base; and operator-privacy levels
OP-1..OP-4. ASSESS-001 (v0.8.1) covered the implementation broadly. This assessment re-tests the current main under
that model and goes further on derived information, forged access state, operator paths, and the TCB.

**How:**
- Source review of hosted/, shared/, core/, and the release and deployment files.
- 17 runtime tests in [hosted/test/assessment/assess002_test.exs](../../../hosted/test/assessment/assess002_test.exs),
  run twice with identical results (17 of 17). Each test prints its evidence line (E-1nn).
- The full hosted suite: 474 of 474, which includes the existing regression tests for ASSESS-001's findings.
- `mix hex.audit`; sobelow; a sweep for dangerous calls; a secrets scan of the 17 commits since ASSESS-001.
- Reproduce with:

  ```sh
  cd hosted && MIX_TEST_PARTITION=_a2 mix ecto.create && MIX_TEST_PARTITION=_a2 mix test test/assessment --trace
  ```

**Scope:** the hosted form is the subject, because the brief's model is a SaaS. The local-first form shares
shared/ and core/, which are assessed here. Its vault-file attack surface is ASSESS-001's and DEF-028's.

## Mitigation (WI-085, REV-113)

ACT-001 approved CP-028 (REV-113). Stage 1, WI-085, is built on this branch and tested (TEST-RUN-028); stage 2 is
DESIGN-002 for both forms, after the independent review. The assessment tests now assert the fixed behaviour
(E-2nn); the E-1nn lines below record main at 5592d94 before it.

| Finding | Severity | Mitigation | Evidence after | Residual |
|---|---|---|---|---|
| FND-201 | MEDIUM | REQ-198: a code over each household's records under HOUSEHOLD_STATE_KEY, checked at every read, written at every change; a join checks first; an audited reseal command | E-212, E-213, E-214 | the operator, who holds the key (E-212r), and a whole-household rollback: DESIGN-002 |
| FND-202 | MEDIUM | REQ-197: the passphrase key under HMAC with PASSPHRASE_PEPPER; 30,371 common passphrases refused | WI-085 tests | a database copy together with the pepper |
| FND-203 | INFO | sessions table private; audit records copied to the log; the console only with an approval reference (REQ-193 AC-3) | E-203; wi084 tests | code run inside the node still reaches keys (accepted, REV-111) |
| FND-204 | LOW | REQ-190 AC-4 per member | E-204 | the household ceiling binds only once a member holds more than the limit by being given items |
| FND-205 | INFO | REQ-199: identifiers derived from the household and number under a server key | E-205 | none |
| FND-206 | LOW | session cookie encrypted | E-217 | none |
| FND-207 | INFO | socket only where the specimen is routed | static | none |
| FND-208 | INFO | x-frame-options DENY | E-116 | the other two observations are product rules |

## Re-run at main 4ac86a7 (2026-10-02)

ACT-001 asked for the assessment to be re-run after WI-085 and for critical items to be flagged, accepted ones
included. Same method, at `review-1`'s code plus four new attacks on WI-085's own controls (E-301..E-304).

**Checks:** the hosted gate exit 0 (hex.audit clean, format, warnings as errors, 488 tests, sobelow clean);
assessment and WI-085 tests twice, 31/31 both; core 201, shared 9, local form 633; the secrets scan over the 5
commits since 5592d94 found nothing; the dangerous-call sweep found nothing reachable. Every original finding's
mitigation still holds (E-203..E-217), and the database still holds no content or secret (E-110).

**New findings:**

| Finding | Severity | Status | What happens | Evidence |
|---|---|---|---|---|
| **FND-209** | MEDIUM | CONFIRMED | Whoever can write the database **and holds an earlier copy of it** (a backup, which database administrators hold) can put a whole household back as it was, code and all, with no key: a revoked grant comes back with no refusal and no notice. WI-085's code stops piecemeal changes (E-302) and forgeries, not this; DEF-077's note said "whoever can write only the database is stopped", which overstated it. | E-301 |
| **FND-210** | LOW | CONFIRMED | The per-member item limit (WI-085) counts items a member is given, and a sole owner can hand a money item to another member without their agreement (REQ-107: only current owners consent to an owner change, except for values and plans). One member can fill another's limit so they can't add anything of their own until they delete what they were given. | E-304 |
| FND-211 | INFO | INFERRED | The `accounts` rows aren't covered by REQ-198. A database writer who copies one account's wrapped key over another's can sign in as that account with their own passphrase, but gets their own key: the membership's key box and the pinned keys don't open, so no content is reached; the result is a broken session (a 500) and a member locked out. | source (accounts.ex sign_in; domain.ex view) |
| — | HELD | | A made-up request identifier, another household's, or a plain number matches nothing (422), and the real request is untouched. | E-303 |

**Remediation:**

- **FND-209:** a per-household counter covered by the code and also kept outside the database: in an append-only
  store, or at least shown to each member at sign-in, as DESIGN-002's visible counter (detection only). DESIGN-002
  section 2.5 already says a checkpoint kept beside the data can't detect a whole rollback and proposes the visible
  counter and an optional outside checkpoint; FND-209 shows the hosted form needs one of them as much as the local
  form. This belongs to the reviewer's DESIGN-002 question 3.
- **FND-210:** count only items a member made or accepted, or require the receiving member's agreement before an
  item becomes theirs. The second also answers a long-standing PRI-002 question (being made an owner without
  agreeing).
- **FND-211:** cover the account's key fields with a code under the same server key, or accept it as availability
  only.

### Resolution (WI-086, REV-114, 2026-10-02)

ACT-001 approved building the items that could be built now (CP-029). WI-086 is built and tested (TEST-RUN-030)
and merged into main at f6cb0e0.

| Flagged item | What WI-086 did | Evidence after | Remaining |
|---|---|---|---|
| 4. Rollback from a database copy (FND-209) | a change counter bound into each household's block and code, and appended to a file outside the database on every commit; a lower counter is refused | E-301, E-302; WI-086 tests | the operator, who can write both; the counter is deliberately not shown to members (it would count others' private changes) |
| 5. Plaintext structure, hosted part (ASM-020) | each household's records as one AES-256-GCM block under a server key; display names encrypted (REQ-200); the per-item tables are gone | E-110, E-212 | the local form's file (with DESIGN-002, after the review); the operator holds the key |
| 8. Filling another's limit (FND-210) | REQ-115 for every item: nobody becomes an owner without agreeing; giving waits for the receiver | E-310; contract suite | none |
| FND-211 | a key not matching its account refused at sign-in and recovery | WI-086 tests | availability only |
| 1, 2, 3, 6, 7 | not built: the review (yours), DESIGN-002 (after the review), client-side encryption and a cooling-off period (your decisions) | | as listed below |

### Flagged items, accepted ones included

None reaches CRITICAL under the brief's scale (no unauthenticated or member-level path to another household's or
another member's content). These are the items that matter most for any decision to put the system in front of
people, ranked:

| # | Item | Form | Rating | Accepted? | Why it is flagged |
|---|---|---|---|---|---|
| 1 | **No independent review** of the cryptography or the code (DEF-026) | both | BLOCKING | no | Every security property here was established by the same AI system that wrote the code. Nothing should go in front of a household before `review-1` is reviewed. |
| 2 | **A member who can edit the vault file can forge agreements, remove people, and roll the file back** (DEF-028) | local | HIGH | no (DESIGN-002 chosen, not built) | This is the study's form and its central adversary: a partner on the shared device. Content stays sealed, but who can see what, and what was agreed, can be changed. |
| 3 | **The operator can read every signed-in member's information** (FND-203) | hosted | HIGH (would be CRITICAL against the brief's operator-isolation goal) | **yes** (REV-111, disclosed by REQ-180) | Operator-privacy level is OP-1: runtime, deployment, or host access is enough, alone. Acceptable only while members are told plainly and the operator is accountable (OPS-001). |
| 4 | **Rolling a household back with a database copy** (FND-209, part of DEF-077) | hosted | MEDIUM | no | Undoes revocations and departures silently, for every household in the copy, without the operator's keys. |
| 5 | **Who owns and sees what is plaintext** (ASM-020) | both | MEDIUM | **yes** | Locally, a member with the file can see how many items another member holds that they can't see, and with whom each is shared; in the hosted form the database and operator can. In financial control between partners the structure itself can be the sensitive fact. |
| 6 | **Coerced consent can't be detected** (DEF-016) | both | MEDIUM | **yes** (study screening) | No technical control exists; the study screens out households with safety concerns. |
| 7 | **The forged-agreement path remains for the operator** (DEF-077, E-212r) | hosted | MEDIUM | partly (trusted operator) | Closed only by DESIGN-002. |
| 8 | **One member can fill another's item limit** (FND-210) | hosted | LOW | no | A small, real lever for one member against another. |

---

## 1. Results at a glance

| | |
|---|---|
| **Inter-household isolation (ISO-1)** | Held: 15 cross-household requests by identifier, no content, no rows changed (E-101) |
| **Person privacy (ISO-2)** | Held: a hidden item is indistinguishable from a missing one (E-103); 11 pages byte-identical for another member after private items are added (E-102) |
| **Derived confidentiality (DER-1)** | Held for every page and total tested (E-102). **Two counting channels leak:** how many items others hold (E-104, LOW) and how many requests others make (E-105, INFO) |
| **Sharing (DEL-1, DEL-2)** | Held: a grantee can't reshare, revoke, change owners, delete, or add readings (E-106) |
| **Revocation (REV-1)** | Held, bound = the next request: revoked grant (E-107), leaving (E-108), passphrase change (existing tests). No cache, no background job, no LiveView |
| **Integrity against a database writer (DI-1)** | **Failed:** a forged request with a forged agreement gets an honest owner to share an item (E-112); deleting an owner's row makes the next save drop their key for good (E-113). Planting a reader still gains nothing (E-114) |
| **Ordinary operator isolation (OI-1/OI-2)** | Database and backup path: ciphertext only (E-110), but offline passphrase guessing is possible (FND-202). Runtime, deployment and host-root paths: **plaintext for signed-in members** (E-111), by design (REV-111) |
| **Operator-privacy level** | **OP-1** overall. The database and backup paths alone are cryptographically protected, but the server holds signed-in members' keys, so the system is not OP-2 or OP-3 |
| **Customer-authorized elevation (OE-1..OE-4)** | **Not implemented, by decision:** the operator is trusted with standing access, as disclosed at sign-up (REQ-180, REV-111) |
| **Emergency access (EM-1, EM-2)** | **Failed, technically:** the break-glass console is enabled by one operator alone and recorded. The second approval is policy (DEPLOY.md §5) |
| **Providers, money movement (PC-1, PC-2, MM-1)** | Not applicable / held: no provider, OAuth, webhook, HTTP client, mail, or payment code or dependency (E-013) |
| **Logs (DM-1, SC-1)** | Held at debug level: parameters filtered, no content, secrets or tokens (E-115). **But** item names travel in the signed, unencrypted session cookie (E-117, LOW) |
| **Provider-organization resistance (SD-1)** | Honest: the system claims no resistance to its operator. Deployment authority can capture plaintext |

**Findings:** 2 MEDIUM, 2 LOW, 4 INFO; none CRITICAL or HIGH. Section 9 has the details.

---

## 2. Architecture model (canonical concepts)

### 2.1 Components and trust boundaries

```
 Browser ──TLS──▶ Reverse proxy (operator's; HSTS) ──loopback──▶ Phoenix release (Bandit, 127.0.0.1)
   │ HttpOnly cookie: signed session token + flash                │  Sessions (ETS, memory only): unwrapped member keys
   │                                                              │  Limits, Forms (ETS); no jobs, no PubSub use, no cache
   │                                                              ▼
   │                                      PostgreSQL (TLS verify-full unless on loopback)
   │                                        runtime role findependence_app: rows only, audit add-only
   │                                        owner role findependence_owner: migrations only
   ▼
 Member's secrets: passphrase (≥12 chars) and recovery key (160 bits), never stored
```

| Boundary | Separates | Enforced by |
|---|---|---|
| B1 Internet / application | P1 from everything | TLS at the proxy; CSRF; parameter shapes; body limits; attempt limits; sign-in |
| B2 Household / household | ISO-1 | the household comes only from the server-side session (REQ-186); every query filters on it (E-004) |
| B3 Member / member | ISO-2, DEL, DER | core rules at every read (`View.visible?`, `Household.pending`); per-item encryption sealed to readers (E-005) |
| B4 Application / database | OI-2 (database path), DI-1 | content and keys encrypted (E-110); **access structure plaintext and unauthenticated** (E-112, E-113) |
| B5 Member secret / server | OI (at rest) | PBKDF2-SHA256 (600,000 iterations) wraps the member's private key (E-006) |
| B6 Operator / runtime | OI (in use) | **none technical**: trusted operator (REV-111); console off by default and audited; no dumps; ptrace blocked (E-009, E-010) |

### 2.2 Resource model and information domains

An item's domain follows its state: **D1** while one owner and no grantees; **D2** with grantees; **D3** with
several owners (joint). Values and plans follow the same rule. Shared values and plans are D3 by consent.

| Resource | Primary domain | Owner | Encryption | Plaintext metadata |
|---|---|---|---|---|
| Money item (name, amount, schedule) | D1 / D2 / D3 by state | its owners | AES-256-GCM per item, key sealed to each reader, Ed25519-signed | id, owners, grantees |
| Value | D1 / D3 (shared) | its owners | as items | as items |
| Account or debt | D1 / D2 / D3 | its owners | as items | as items |
| Reading (balance, rate, payment) | as its item | the item's owners | per reading key, sealed per REQ-132, signed | item id, sequence |
| Ledger entry (history) | as its item, owners only | the item's owners | per entry, sealed to owners, signed | item id, sequence |
| Personal record (links, plans, marks, goals, retirement, attachments, deletion records) | D1 always | the member | under the member's personal key | membership id |
| Shared plan | D3 | its owners (by consent) | as items | as items |
| Request (proposal) and agreements | D3 metadata (visible to the item's owners) | — | **none** | number, item, kind, proposer, targets, agreements |
| Membership, display name | D3 | the member | none | all |
| Invitation code | D5 | its creator | SHA-256 hash only | household, creator, times |
| Account: wrapped private key, number | D5 | the member | KEK from passphrase or recovery key; number HMAC-keyed, and encrypted | id, public keys, salts, iterations |
| Session (unwrapped keys) | D5 | the member | **memory only, plaintext** | — |
| Audit event | D4 | — | none (content-free) | all |
| Derived: home totals, 14/60-day running balance, 12-month projection, value distribution, goals, retirement projection | D1 (of the requester) | the requester | not stored | — |
| Export file | D1 (the requester's) | the requester | none (a download) | — |
| Server secrets: SECRET_KEY_BASE, ACCOUNT_HMAC_KEY, RELEASE_COOKIE, DB passwords | D5 | the operator | environment / secret manager | — |

### 2.3 Principals

| Type | Instances in this system |
|---|---|
| P1 | Any internet client: sign-up, sign-in, recovery, health endpoints, static files |
| P2 | A signed-in member, simultaneously owner, grantee, co-owner, proposer, and agreer |
| P3 | **None.** There is no household administrator; any member may invite (REQ-185), and no one has authority over another's items (DP-001) |
| P4 | Whoever runs the service: host login, database administration, deployment. **One undivided role** (REV-111; DEPLOY.md) |
| P5 | **None.** No elevation mechanism exists |
| P6 | **None** as a distinct mechanism; the break-glass console is a P4 capability under a written procedure |
| P7 | The release (runtime DB role), the migration runner (owner role), PostgreSQL, the reverse proxy |
| P8 | Anyone able to change the release or the host |

### 2.4 Relationships and actions

| Relationship | Stored as | Confers |
|---|---|---|
| MEMBER_OF | `memberships` row; the session's membership | household pages; nothing about anyone's items |
| OWNS | `item_readers` role owner + a sealed key | VIEW, MODIFY (readings), DELETE (sole), SHARE (propose, consent), REVOKE, EXPORT, history VIEW |
| SHARED_WITH | `item_readers` role grantee + a sealed key | VIEW (and an account's latest reading) |
| APPROVES | `proposal_members` role consent | completes a request when every owner (and a value's or plan's joiner) has agreed |
| DERIVED_FROM | computed per request from the requester's visible items | VIEW of the derived value only |
| OPERATES | host, database, release | everything the server holds (P4) |

### 2.5 Authorization function as implemented

```
allow(member, item, action) =
  member's household = session household                                  (B2; Tenancy, Domain.load/1)
  ∧ core rule for action over the member's view:
      VIEW    : member ∈ owners ∪ grantees               (View.visible?/3)
      MODIFY  : member ∈ owners                           (Balances.add_reading, owned_item/3)
      SHARE   : member ∈ owners, applied when owners ⊆ agreements (Household.apply_if_consented/2)
      REVOKE  : member ∈ owners                           (revoke_grant/4)
      DELETE  : owners = {member}                         (Exit.delete/3)
      EXPORT  : items with member ∈ owners, and the member's own records (REQ-169)
  ∧ cryptographically: member holds a seal of the item key that verifies (Envelope.build/2)
```

It never relies on ID secrecy (item IDs are 72 random bits, but nothing depends on that), UI state, hidden
controls, or client state. Every page reloads the household from the database (no cached authorization).

---

## 3. Authorization matrix (observed)

`✓` allowed, `✗` refused, `—` no such action. The expected and observed decisions agree everywhere tested.

| Principal | Resource (domain) | Relationship | VIEW | CREATE | MODIFY | DELETE | SHARE | EXPORT | ADMIN | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|
| Owner | own private item (D1) | OWNS | ✓ | ✓ | ✓ readings | ✓ sole | ✓ | ✓ | — | suite; E-109 |
| Other member | that item (D1) | MEMBER_OF | ✗ (404, same as missing) | — | ✗ | ✗ | ✗ | ✗ | — | E-102, E-103 |
| "Administrator" | any (D1) | — | no such role | | | | | | | P3 none |
| Grantee | shared item (D2) | SHARED_WITH | ✓ | — | ✗ (422) | ✗ (422) | ✗ reshare (422) | ✗ not in export | — | E-106, E-109 |
| Grantee | an adjacent item | MEMBER_OF | ✗ | | | | | | | E-102 |
| Revoked grantee | formerly shared item | MEMBER_OF | ✗ next request | | | | | ✗ | | E-107 |
| Co-owner | joint item (D3) | OWNS | ✓ | — | ✓ | ✗ (not sole) | ✓ by all owners | ✓ | — | suite |
| Other household | any | none | ✗ (404) | ✗ | ✗ (422) | ✗ (422) | ✗ (422) | ✗ | — | E-101 |
| P4 database / backup | all rows | OPERATES | ciphertext + metadata | ✓ rows | ✓ rows (DI-1 fails) | ✓ rows | forges agreements | — | — | E-110, E-112, E-113 |
| P4 runtime / deploy / root | signed-in members' content | OPERATES | **✓ plaintext** | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | E-111 |
| P5 elevated operator | — | — | no such principal | | | | | | | — |

---

## 4. Delegation matrix

| Grant type | Grantor | Grantee | Resource scope | Action scope | Purpose | Expiry | Revocable | Observed enforcement | Evidence |
|---|---|---|---|---|---|---|---|---|---|
| Item grant | every current owner (agreement) | one member of the same household | one item (its latest reading for accounts and debts; not its history) | VIEW | not recorded | none | yes, by any one owner, effective at the next request | held | E-106, E-107 |
| Joint ownership | every current owner (+ the joiner for values and plans) | one or more members | one item | all owner actions | — | none | the co-owner may relinquish; removal needs all owners | held via the application; **forgeable in rows** | E-112, E-113 |
| Shared value or plan | owners + each joiner | members | one value or plan | owner actions | — | none | relinquish, withdraw | suite (REQ-148) | suite |
| Operator elevation | — | — | — | — | — | — | — | **not implemented: the operator has standing access** | REV-111 |

Person-to-person sharing is coherent: explicit grantor, grantee and scope, single action, revocable. It has no
purpose or expiry fields. These are product choices, not defects. The operator side has no delegation at all,
so the two cannot share one model (completion criterion 4: not met, by design).

---

## 5. Operator access matrix

| Operator role | Standing D4 metadata | Standing financial content | Database | Runtime | Backups | Observability | KMS | Can request elevation | Can approve own | Emergency authority | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Database administrator (runtime or owner role, or superuser) | yes: ids, owners, grantees, requests, display names, audit | **no**: ciphertext; offline passphrase guessing possible | full rows | no | yes | — | none exists | — | — | — | E-110; FND-202 |
| Host operator (login, systemd) | yes | **yes, for signed-in members**: restart with OPERATOR_CONSOLE=on (recorded), or change the release | via the release's credentials | yes | per deployment | logs: no content | — | — | **yes, alone** | yes, alone | E-111; E-009 |
| Deployer (builds and installs releases) | yes | **yes**: can change code to capture passphrases at sign-in | via the release | yes | — | — | — | — | yes | yes | SD-1 |
| Support | **no such role or tooling** | | | | | | | | | | — |

There are no support interfaces, no impersonation, and no admin pages in the code (router, E-001).

---

## 6. Revocation test matrix

| Authority removed | Expected bound | Observed | Status | Evidence |
|---|---|---|---|---|
| Sharing revocation | next request | the next item page, home and export lack it | EFFECTIVE | E-107 |
| Household removal (only by leaving; no one can remove another) | immediate | every session of the leaver ends; no session holds their key | EFFECTIVE | E-108 |
| Role reduction (relinquishing ownership) | next request | the same per-request reload as a revocation | EFFECTIVE (INFERRED from E-107's mechanism, suite) | suite |
| Account disablement (deletion, after leaving) | immediate | sessions dropped, key material removed | EFFECTIVE | suite (REQ-189) |
| Passphrase change | immediate, for other sessions | other sessions end | EFFECTIVE | suite (REQ-183 AC-2) |
| Operator-elevation expiry or revocation | — | no elevation exists | NOT APPLICABLE | — |
| Emergency-access expiry | — | the console stays on until the operator restarts without it | INEFFECTIVE (policy only) | E-009; DEPLOY.md §5 |
| Provider-token revocation | — | no providers | NOT APPLICABLE | E-013 |
| Active HTTP session | next request | membership and household re-read on every request | EFFECTIVE | E-107, E-108 |
| Active LiveView / WebSocket | — | no LiveView route in production; the `/live` socket is mounted but nothing can join it | NOT APPLICABLE (FND-207) | E-001, E-002 |
| Cached derived output | — | none: every page recomputes from the database; `cache-control: no-store` | EFFECTIVE | E-102, E-116 |
| Background job | — | none: the only timers are the session, limit and form-token sweeps | NOT APPLICABLE | E-003 |
| Export URL | — | none: the export is generated in the response; no stored file or URL | NOT APPLICABLE | E-109 |
| Copies already exported or seen | — | a grantee's earlier view, and the owner's exports, persist outside the system | product semantics | — |

**Effective revocation latency:** the next request (three requests in 3 ms after revocation, E-107). Every page
reloads the household from the database, so there is no cached view to outlive a grant.

---

## 7. Trusted computing base and minimum compromise sets

| TCB component | Authority held | Resources reachable | Invariants dependent | Alone defeats protection? | Evidence |
|---|---|---|---|---|---|
| Phoenix release (code + node) | unwrapped keys of signed-in members; all rows | all content of signed-in members; all metadata | ISO, DEL, REV, DER, OI | **yes**, for signed-in members (and for others at their next sign-in) | E-111 |
| Deployment pipeline (none automated: whoever builds and installs) | replace the release | as above, plus every passphrase typed | all | **yes** | SD-1 |
| Host root | restart with the console, replace the release, read the environment | as the release | all | **yes** (ptrace is blocked by yama scope 3, but restart or replace isn't) | E-010 |
| PostgreSQL / runtime DB role | read and write rows | ciphertext, wrapped keys, access structure | DI-1, OI-2 | **DI-1: yes** (E-112, E-113); confidentiality: no, unless a passphrase is guessed (FND-202) | E-110 |
| DB owner role / superuser | drop the audit trigger, change the schema | audit records | OE-4 | audit integrity: yes | E-007 |
| Backups (operator's; not in the repository) | copies of rows | as the database, read-only | OI-2, SC-1 | confidentiality: no, unless a passphrase is guessed | DEPLOY.md §1 |
| SECRET_KEY_BASE | sign session cookies | forge a cookie, but the token is random and server-side | — | no: a forged cookie needs a live token | E-002, E-003 |
| ACCOUNT_HMAC_KEY | find accounts by number | account lookup | sign-in | no (still needs the passphrase) | E-006 |
| RELEASE_COOKIE | connect a console when distribution is on | the node | all | only with the console enabled | E-009 |
| Reverse proxy / TLS | terminates TLS | every request, passphrases in transit | all | **yes** (sees passphrases) | DEPLOY.md §3 |
| Audit system (same database) | records | — | OE-4 | — | E-007 |
| Identity provider, KMS/HSM, support service, delegation service, emergency service, CI/CD, observability | **none exist** | | | | E-013 |

**Minimum compromise sets for protected financial content:**
1. code execution in the release, or deployment authority, or host root, or the TLS terminator (any one; for
   signed-in members, or everyone at their next sign-in);
2. a database or backup copy **and** a guessable passphrase (per member) or that member's recovery key;
3. a member's passphrase and account number (that member's view; attempt-limited online).

**For integrity:** write access to the database alone (forged agreements, removed owners, rollback).

**Who ultimately holds decryption authority:** each member (passphrase or recovery key) and, while they're signed
in, the server process, so the operator too.

---

## 8. Invariant assurance table

| Invariant | Result | Confidence | Primary evidence | Known limitations | Residual risk |
|---|---|---|---|---|---|
| ISO-1 | PROVEN WITH HIGH CONFIDENCE | HIGH | E-101; ASSESS-001 (13 kinds); B2 in code | a database writer can move rows between households (DI-1) | low |
| ISO-2 | PROVEN WITH HIGH CONFIDENCE | HIGH | E-102, E-103 | — | low |
| ISO-3 | PROVEN WITH HIGH CONFIDENCE | HIGH | E-102, E-106 | — | low |
| ISO-4 | NOT APPLICABLE (no administrator role) | HIGH | E-001; DP-001 | any member can admit a new member (FND-208) | low |
| DEL-1 | PROVEN WITH HIGH CONFIDENCE (through the application) | HIGH | E-106; core | forgeable in rows (DI-1) | medium |
| DEL-2 | PROVEN WITH HIGH CONFIDENCE (through the application) | HIGH | E-106 | as DEL-1 | medium |
| REV-1 | PROVEN WITH HIGH CONFIDENCE | HIGH | E-107, E-108 | copies already seen or exported persist | low |
| DER-1 | WEAKLY SUPPORTED | HIGH | E-102 held; E-104, E-105 leak counts | counts only; no amounts or names | low |
| OI-1 | FAILED (by design, disclosed) | HIGH | E-111 | REV-111 accepts it | accepted |
| OI-2 | FAILED for runtime, deployment, root; SUPPORTED WITH MEDIUM CONFIDENCE for the database, backups and logs | HIGH | E-110, E-111, E-115 | offline guessing (FND-202); backups not built | medium |
| OE-1..OE-3 | FAILED (not implemented, by design) | HIGH | REV-111 | — | accepted |
| OE-4 | WEAKLY SUPPORTED | MEDIUM | E-007, E-009 | audit lives in the database the operator controls; off-host shipping is a manual step | medium |
| EM-1 | FAILED | HIGH | E-009 | the console is the only exceptional path, and it is ordinary P4 capability | accepted |
| EM-2 | FAILED (technically); policy requires a second approver | HIGH | DEPLOY.md §5 | — | medium |
| PC-1, PC-2 | NOT APPLICABLE | HIGH | E-013 | — | — |
| DI-1 | FAILED against a database writer; PROVEN against members | HIGH | E-112, E-113, E-114; suite | DESIGN-002 is not built | medium |
| DM-1 | SUPPORTED WITH MEDIUM CONFIDENCE | HIGH | E-110, E-115, E-117 | item names in the cookie (FND-206) | low |
| SC-1 | SUPPORTED WITH MEDIUM CONFIDENCE (logs, database); NOT ASSESSED (backups, replicas, staging: none exist yet) | MEDIUM | E-110, E-115 | — | medium |
| MM-1 | PROVEN WITH HIGH CONFIDENCE | HIGH | E-013, E-015 | — | none |
| SD-1 | HELD (the system makes no claim to resist its operator) | HIGH | REQ-180; REV-111 | — | — |
| UA-1 | PROVEN (each item shows who else can see it; the ledger lists grants) | HIGH | suite (REQ-105, REQ-129 AC-6) | no single "everything I've shared" page | low |
| UA-2 | PROVEN | HIGH | E-107 | — | low |
| UA-3 | PROVEN WITH HIGH CONFIDENCE | HIGH | E-109 | — | low |
| UA-4 | PROVEN (application); FAILED against a database writer | HIGH | suite; E-113 | — | medium |
| UA-5 | PROVEN | HIGH | E-102, E-108 | — | low |

---

## 9. Findings

Each finding's machine-readable form is in [ASSESS-002-findings.json](ASSESS-002-findings.json).

### FND-201 (MEDIUM, CONFIRMED). The hosted form's access state is unauthenticated: whoever can write the database can forge requests and agreements, and can remove an owner for good

- **Invariants:** DI-1, DEL-1, DEL-2, UA-4. **Resources:** requests, agreements, `item_readers` (D2, D3).
- **Principals:** P4 database administrator; P7 runtime role credentials if stolen; anyone restoring a tampered
  backup.
- **Attack path (E-112):**
  1. Insert a request "share the joint item with Ben", recorded as proposed by Cal, with Cal's agreement.
  2. Ana's home page shows it as "Agreed so far: Cal". Ana agrees.
  3. The rules apply it, and Ana's save seals the item key to Ben, who now reads the item.
  4. No integrity issue is reported.
- **Second path (E-113):**
  1. Delete Cal's owner row.
  2. Ana's next change saves the item without Cal's key.
  3. Put the row back: Cal can no longer read the item.
- **Why the existing mitigation is insufficient:**
  - Seal commitments (WI-079) stop a planted reader from being handed a key (E-114, held).
  - Signatures cover content, entries and readings.
  - But owners, grantees, requests and agreements are plain rows that nothing authenticates. This is DEF-028's
    weakness in the hosted form.
  - Under REV-111 the operator is trusted, so this matters for a database compromise that isn't the operator:
    leaked runtime credentials, a restored backup, or a database administrator who is a different person.
- **Remediation (preferred):** extend DESIGN-002 (the signed operation log, CP-027 A) to the hosted form. Every
  change to the access state is signed by the members whose consent it needs and verified on load. A request or
  agreement without a valid signature is shown as an integrity issue and never applied.
- **Alternative:** the server signs the access state with a key outside the database. This protects against a
  database-only writer but not against the operator.
- **Regression tests:** E-112 and E-113 must show the forged request refused and Cal's key kept.
- **Mapping:** ASVS V4.1 (access control enforced on trusted data), V8.3; CWE-345, CWE-639. **Defeater:** DEF-077.

### FND-202 (MEDIUM, CONFIRMED mechanism; exploitability INFERRED). A database or backup copy allows offline guessing of members' passphrases

- **Invariants:** OI-2, SC-1. **Resources:** D5 wrapped private keys, and through them all of a member's D1–D3
  content.
- **Mechanism:** `accounts.private_key_by_passphrase` is wrapped under PBKDF2-HMAC-SHA256 with 600,000 iterations
  and a per-account salt, with the iteration count stored beside it (E-006). The derivation uses nothing held
  outside the database. The only rule on passphrases is at least 12 characters.
- **Impact:** a copy of the database (or of a backup, kept 35 days, deleted accounts included) lets an attacker
  test guesses offline, without the attempt limits. A weak passphrase, guessed, yields that member's private key:
  everything they can read, plus the ability to sign as them.
- **Existing mitigation:** 600k iterations meets REQ-118 and OWASP's current PBKDF2 guidance. The recovery key
  (160 random bits, HKDF) is not guessable.
- **Remediation (preferred):** mix a server-held pepper into the key-wrapping key, e.g. HMAC with a secret kept
  outside the database (a secret manager, or the KMS a deployment provides). A database or backup copy alone then
  allows no guessing at all.
- **Also:** reject the most common passphrases at sign-up and passphrase change. Consider a memory-hard KDF if one
  becomes available without a third-party cryptography library.
- **Regression test:** with the pepper absent, no stored wrapped key opens.
- **Mapping:** ASVS V2.4.1, V2.4.5 (a secret salt known only to the verifier); CWE-916, CWE-521. **Defeater:** DEF-078.

### FND-203 (INFO, accepted by design). The operator holds signed-in members' keys, with no customer-authorized elevation and no separate emergency mechanism

- **Invariants:** OI-1, OI-2, OE-1..OE-4, EM-1, EM-2.
- **Observed (E-111):** code running in the node read the `Sessions` table, which is `:public`, and decrypted a
  signed-in member's item outside any request.
- **The console:** it is off unless one operator restarts with `OPERATOR_CONSOLE=on`. That boot is recorded, and so
  is each connection, but in the database the operator administers. The second approval and the off-host audit
  copy are procedures (DEPLOY.md §5, §6).
- **Why this is INFO:** REV-111 chose this model (CP-024 A), and REQ-180 tells members before sign-up. So the
  finding is the honest OP-1 statement, not a defect.
- **Defense in depth:**
  - make the `Sessions` table `:protected`, read only through its process;
  - ship audit records off-host continuously rather than by a manual command;
  - have the boot record name the approval reference;
  - if the brief's OE model is wanted, it needs a different architecture (ARCH-004 section 5's client-encrypted
    options).
- No Defeater: decided in REV-111. This assessment is new evidence for CP-024's record.

### FND-204 (LOW, CONFIRMED). The household's item limit tells a member how many items others hold

- **Invariants:** DER-1, ISO-2.
- **Observed (E-104):** with the limit at 5, Ben could add 2 items before "household full", so Ben learns that Ana
  holds 3 he can't see. At the real limit (2,000), a member can count everyone else's items by adding and deleting.
- **Remediation:** a per-member limit that binds first (for example 2,000 per member, with a household ceiling high
  enough never to bind first). Or answer "you have reached your limit" from a per-member count only.
- **Mapping:** CWE-203. **Defeater:** DEF-079.

### FND-205 (INFO, CONFIRMED). Request numbers count every request in the household

- **Observed (E-105):** Ben's request is number 4 after two requests he had no part in. He learns that others are
  sharing or changing ownership, but not what, or between whom.
- **Remediation:** random request identifiers (as item identifiers are), or numbering per member.
- **Mapping:** CWE-203. **Defeater:** DEF-079.

### FND-206 (LOW, CONFIRMED). Confirmation messages carrying item names travel in a signed but unencrypted session cookie

- **Invariants:** DM-1.
- **Observed (E-117):** after adding "Cookie visible note", the session cookie's payload decodes to text containing
  the name, with no key needed. The cookie is HttpOnly and Secure, so the exposure is to the browser's cookie
  store and to any TLS-terminating component that logs cookies.
- This is ASSESS-001's FND-15, which WI-079 fixed in the local form only.
- **Remediation:** set `encryption_salt` on the hosted session (endpoint.ex), as the local form does.
- **Regression test:** E-117 inverted.
- **Mapping:** ASVS V3.2; CWE-315. **Defeater:** DEF-079.

### FND-207 (INFO, CONFIRMED). The LiveView socket is mounted in production with nothing to serve

- `socket "/live"` is mounted (endpoint.ex). The only LiveView, `/specimen`, isn't routed in production, so
  nothing can join it: joining needs a signed session token for a routed view.
- **Remediation:** mount the socket only where the specimen is (`:specimen_route`), to shrink the surface.
- **Defeater:** DEF-079.

### FND-208 (INFO). Smaller observations

- `x-frame-options` is absent (E-116). CSP `frame-ancestors 'none'` covers current browsers.
- Any one member can admit a new member with an invitation (REQ-185). The new member learns every member's display
  name, and the counts in FND-204 and FND-205. This is a product rule, not a defect.
- Revoking a grant re-seals nothing: content is immutable (ASM-021), so a former grantee keeps only what they
  already saw. In the hosted form members never hold raw keys.

No Defeater.

---

## 10. Attack-surface matrix

| Surface | Authentication | Principal | Resource / domain | Authorization boundary | Delegation boundary | External input | Invariants | Status | Evidence |
|---|---|---|---|---|---|---|---|---|---|
| /sign-up, /sign-in, /recover | none | P1 | D5 account | attempt limits, sign-up limit | — | form fields | ISO-1, DM-1 | assessed | suite; ASSESS-001 |
| Domain pages (GET) | session | P2 | D1–D3, derived | session household; core visibility | grants | ids in paths | ISO-1/2/3, DER-1 | assessed | E-101..E-105 |
| /act/*, /confirm/* (POST) | session + CSRF + form token | P2 | D1–D3 | core rules | grants, agreements | ids, amounts, text | DEL-1/2, DI-1 | assessed | E-101, E-106 |
| /export.json | session | P2 | D1 (own) | owner-only scope | — | — | UA-3 | assessed | E-109 |
| /act/bring-in | session | P2 | D1 (own, new) | strict decoder, 1 MB, counts | — | an untrusted JSON file | DI-1, DM-1 | assessed (ASSESS-001; suite) | E-021 |
| /household, /join, /invitations | session | P2 | D3 membership | code hash, limits | — | code, name | ISO-1 | assessed | suite |
| /health/live, /health/ready | none | P1 | D4 | none needed | — | — | — | assessed | suite (wi084) |
| /live socket | none to connect | P1 | none | signed view token | — | WebSocket | — | partially assessed (static) | FND-207 |
| Static files | none | P1 | public assets | — | — | — | — | assessed | E-002 |
| Distribution / console | cookie, only when enabled | P4 | everything | none beyond the cookie | — | — | OI, EM | assessed | E-009 |
| PostgreSQL | DB roles, TLS | P4, P7 | all rows | role grants | — | SQL | OI-2, DI-1 | assessed | E-008, E-110, E-112 |

## 11. Data-flow register

| Resource | Domain | Owner | Source | Derived from | Sensitivity | Storage | Browser exposure | Log exposure | Ordinary-operator exposure | Elevated | External recipients | Retention / deletion | Encryption |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Money item | D1–D3 | owners | member's form, bring-in | — | high | items (ciphertext) | its readers' pages; flash cookie (FND-206) | none (E-115) | DB: ciphertext; runtime: plaintext if signed in | n/a | none | until deleted; backups 35 days | AES-GCM, sealed, signed |
| Reading | as item | owners | form | — | high | readings | readers (latest), owners (all) | none | as above | n/a | none | as above | as above |
| Ledger entry | as item | owners | each change | — | medium | ledger_entries | owners | none | as above | n/a | none | as above | as above |
| Personal record | D1 | member | forms | — | high | personal_records | the member | none | as above | n/a | none | removed on leaving | AES-GCM under the personal key |
| Requests, agreements, owners, grantees | D3 meta | — | actions | — | medium | proposals, proposal_members, item_readers | owners of the item | none | **plaintext, writable** (FND-201) | n/a | none | until applied or withdrawn | none |
| Display name, membership | D3 | member | form | — | low–medium | memberships | household members | none | plaintext | n/a | none | removed on leaving | none |
| Account keys | D5 | member | sign-up | passphrase, recovery key | critical | accounts | never | none | ciphertext; guessable offline (FND-202) | n/a | none | removed on deletion; backups 35 days | PBKDF2 / HKDF + AES-GCM |
| Account number | D5 | member | sign-up | — | medium | accounts (HMAC, box) | shown once, then on /household | none | HMAC only | n/a | none | as account | HMAC-SHA256; AES-GCM |
| Session keys | D5 | member | sign-in | — | critical | memory (ETS) | token in cookie only | none | **runtime: readable** (E-111) | n/a | none | 15 min idle / 12 h | none in memory |
| Derived totals, projections | D1 | requester | computed per request | visible items | high | not stored | requester | none | runtime only | n/a | none | not kept | — |
| Export file | D1 | requester | computed | owned items, own records | high | not stored | the download (no-store) | audit "export" only | runtime only | n/a | the member | the member's copy | none (a file the member holds) |
| Audit event | D4 | — | events | — | low | audit_events (append-only) | never | — | plaintext | n/a | off-host by procedure | kept | none |

## 12. Threat model (implementation-specific)

| Threat | Path | Holds? |
|---|---|---|
| Inter-household access | identifier substitution in paths and forms | yes (E-101) |
| Intra-household snooping | pages, totals, projections | yes (E-102); counts leak (FND-204, FND-205) |
| Derived inference | aggregates computed only over what the requester sees (REQ-106) | yes, except the counts |
| Account takeover | number + passphrase online, attempt-limited; recovery key 160 bits | yes online; offline from a database copy (FND-202) |
| Grantee escalation | reshare, revoke, owners, delete, readings | yes (E-106) |
| Stale access | revoked grant, leaving, passphrase change | yes, next request (E-107, E-108) |
| XSS → session theft | HEEx escaping; CSP without inline script; HttpOnly cookie | yes (suite; ASSESS-001); no `raw` (E-015) |
| CSRF | tokens + one-time form tokens; SameSite=Lax | yes (suite) |
| Operator reading content | runtime, deployment, root | **no, by design** (FND-203) |
| Database compromise | read: ciphertext (E-110); write: forged access state (FND-201) | read yes; write no |
| Backup compromise | as a database read; offline guessing | partly (FND-202) |
| KMS compromise | no KMS exists | n/a |
| Deployment compromise | modified release captures passphrases | no (SD-1, accepted) |
| Provider compromise | no providers | n/a |
| Telemetry leakage | parameters filtered; no external telemetry or analytics | yes (E-115) |
| Availability | attempt, sign-up and write limits; 2,000-item ceiling; 1 MB bring-in; 100 kB forms | partly (ASSESS-001 FND-10 mitigated) |
| Supply chain | lockfile hashes, hex.audit clean, Tailwind digest pinned; container images not pinned | partly (DEF-076 note) |

## 13. Completeness table

| Area | Status | Note |
|---|---|---|
| System architecture | ASSESSED | §2 |
| Resource model | ASSESSED | §2.2 |
| Information domains | ASSESSED | domain by item state |
| Derived information | ASSESSED | E-102, E-104, E-105 |
| Principal model | ASSESSED | P3, P5, P6 absent |
| Relationship model | ASSESSED | §2.4 |
| Delegation model | ASSESSED | §4 |
| Authorization | ASSESSED | §3 |
| Inter-household isolation | ASSESSED | E-101 |
| Person privacy | ASSESSED | E-102, E-103 |
| Shared-scope integrity | ASSESSED | E-106 |
| Household administration separation | NOT APPLICABLE | no administrator role |
| Revocation | ASSESSED | §6 |
| Derived confidentiality | ASSESSED | |
| User sharing visibility | ASSESSED | suite |
| Portability | ASSESSED | E-109 |
| Deletion integrity | ASSESSED | suite; E-113 |
| Ordinary operator isolation | ASSESSED | E-110, E-111 |
| Alternate operator paths | PARTIALLY ASSESSED | database, runtime, logs tested; backups, replicas, staging don't exist yet |
| Operator elevation | NOT APPLICABLE | not implemented (REV-111) |
| Emergency access | ASSESSED | the console |
| TCB | ASSESSED | §7 |
| Malicious-provider / software-update threat | ASSESSED | SD-1 |
| Authentication | ASSESSED | code + suite; ASSESS-001 runtime |
| Sessions | ASSESSED | E-003, E-108, E-117 |
| LiveView | NOT APPLICABLE | no production routes (FND-207) |
| Phoenix configuration | ASSESSED | E-002, E-011, E-116 |
| TLS | PARTIALLY ASSESSED | DB TLS verify in config; the proxy is the operator's (not in the repository) |
| XSS | ASSESSED | suite; no raw output |
| Injection | ASSESSED | no raw SQL with input; Ecto parameters (E-015) |
| BEAM security | ASSESSED | E-009, E-015 |
| Ecto | ASSESSED | E-004 |
| PostgreSQL | ASSESSED | E-008 (roles), E-007 (trigger) |
| RLS | NOT APPLICABLE | isolation by query filter and encryption; ISO-1 demonstrated without RLS |
| Cryptography | ASSESSED | E-005, E-006 (not independent: DEF-026) |
| Key management | ASSESSED | no KMS; member-held secrets |
| Secrets | ASSESSED | E-016 |
| Provider integrations, scopes, credentials, webhooks, synchronization | NOT APPLICABLE | none exist (E-013) |
| Financial integrity | ASSESSED | DI-1; integer cents (E-024) |
| Imports | ASSESSED | ASSESS-001 runtime; limits (E-021) |
| Exports | ASSESSED | E-109 |
| Logging | ASSESSED | E-115 |
| Telemetry | ASSESSED | local metrics only; no exporter |
| Analytics | NOT APPLICABLE | none |
| Backups, replicas, non-production copies | NOT ASSESSED | not built; DEPLOY.md policy only |
| Retention | PARTIALLY ASSESSED | code paths; backups by policy |
| Deletion | ASSESSED | suite (REQ-108, REQ-189) |
| Availability | PARTIALLY ASSESSED | limits tested by suite; no load test this time |
| CI/CD | NOT APPLICABLE | none: releases are built by hand from tags |
| Supply chain | ASSESSED | E-013, E-014 |
| Infrastructure | NOT ASSESSED | no infrastructure exists; DEPLOY.md and the preflight check define it |

## 14. Evidence index

| ID | Kind | Source |
|---|---|---|
| E-001 | source | hosted/lib/findependence_hosted_web/router.ex (routes; `/specimen` only when `:specimen_route`) |
| E-002 | source | hosted/lib/findependence_hosted_web/endpoint.ex:6-17 (cookie signed, Lax, HttpOnly, Secure; `/live` socket) |
| E-003 | source | hosted/lib/findependence_hosted/sessions.ex (ETS `:public`; idle 15 min, 12 h; drop on leave and passphrase change) |
| E-004 | source | hosted/lib/findependence_hosted/domain.ex:164-312 (per-household queries; access structure as rows) |
| E-005 | source | shared/lib/findependence_shared/envelope.ex:24-38, 766-830 (signatures, seal commitments) |
| E-006 | source | hosted/lib/findependence_hosted/accounts.ex:17-20, 341-374; config/config.exs:15 (PBKDF2 600k, ≥12 chars, 80-bit number, 160-bit recovery key) |
| E-007 | source | audit.ex; migrations/20260930200000_audit_append_only.exs |
| E-008 | source + test | rel/database-roles.sql; release.ex grants; test/findependence_hosted/wi081_roles_test.exs |
| E-009 | source + test | rel/env.sh.eex; test/findependence_hosted/wi084_test.exs |
| E-010 | source + test | preflight.ex (swap, ptrace scope 3, LimitCORE, TLS, roles, cookie); wi084_test.exs |
| E-011 | source | config/runtime.exs (DB TLS verify, PHX_HOST, secrets required, trusted proxies) |
| E-012 | source | config/config.exs:92 (`filter_parameters: {:keep, []}`) |
| E-013 | dependency | hosted/mix.lock: 35 packages; no HTTP client, mail, provider, analytics, or job library |
| E-014 | scanner | sobelow 0.15.0: clean; `mix hex.audit`: no retired or advised packages |
| E-015 | sweep | no reachable String.to_atom, unsafe binary_to_term, eval, shell, `raw`, or SQL built from input |
| E-016 | scan | secrets regex over `git log -p 25508aa..5592d94` (17 commits): none |
| E-017 | source | security_headers.ex (CSP without inline script) |
| E-018 | source | core/lib/findependence/household.ex:84-240 (owners only propose; applied when owners ⊆ agreements; pending visible to owners) |
| E-019 | source | shared/lib/findependence_shared/persistence.ex:31 (72-bit random ids); households.next_proposal (sequential) |
| E-020 | source | hosted/lib/findependence_hosted/operation.ex (household lock, write limit, 2,000 items) |
| E-021 | source | core/lib/findependence/import.ex:18-26; body_parsers.ex (1 MB) |
| E-022 | policy | hosted/DEPLOY.md and OPS-001 (backups, break-glass approval, monthly review, off-host audit): procedures, not code |
| E-023 | test run | hosted suite 474/474 at 5592d94 + the assessment tests |
| E-024 | source | integer cents throughout; one float for months of savings (projection.ex:232) |
| E-101..E-117 | runtime | hosted/test/assessment/assess002_test.exs, printed lines; two runs identical |

## 15. Executive technical summary

- **System assessed:** Findependence hosted form (Phoenix 1.8.15, server-rendered, PostgreSQL 17), with the shared
  and core code it runs; main 5592d94.
- **Context:** a research prototype, not in service. The operator is trusted by decision (REV-111).
- **Evidence available:** source, history, configuration, migrations, a live test database, runtime tests.
- **Evidence unavailable:** no deployment, infrastructure, backups, proxy or CI exist; all are NOT ASSESSED.
- **Architecture and privacy model:** each item is encrypted and sealed to its readers and signed by its writer.
  Visibility is decided by core rules on every request. The server holds a signed-in member's unwrapped key in
  memory.
- **TCB:** the release, its host, whoever deploys it, and the TLS terminator are each sufficient alone. The
  database alone is sufficient for integrity attacks, not for confidentiality.
- **Inter-household isolation:** holds.
- **Personal privacy within a household:** holds.
- **Sharing:** holds through the application. A database writer can forge it (FND-201).
- **Revocation:** holds, bound by the next request.
- **Derived confidentiality:** holds for content; two counting channels leak (FND-204, FND-205).
- **Household administration:** not applicable; no administrator role exists.
- **Operator-privacy level: OP-1.**
- **Customer-authorized operator access:** none; standing access, disclosed.
- **Emergency access:** not distinct from operator access; one operator can enable the console, and it is
  recorded.
- **Provider credentials:** none exist.
- **Financial integrity:** holds against members; fails against a database writer.
- **Data minimization:** holds, except item names in the cookie (FND-206).
- **Secondary-system containment:** logs and database hold; backups aren't built.
- **Provider-organization limitation:** stated honestly; the system doesn't resist its operator.

**Highest-impact confirmed:** FND-201, FND-202.

**Highest-impact unresolved hypotheses:**
- the reverse proxy's and backups' handling of cookies and data once built;
- that no Phoenix default differs in the deployed release (a smoke test against the real host is needed).

**Strong controls positively verified:**
- per-request authorization with no cache;
- hidden equals missing;
- byte-identical pages for other members;
- the grantee's limits;
- immediate session ending;
- the database holding no content or secrets;
- parameter filtering;
- no money-movement capability.

**Must fix before production (hosted):**
- FND-201 (DESIGN-002 for the hosted form, or a server-side signature as an interim);
- FND-202 (pepper);
- FND-206 (cookie encryption).

**High priority:** FND-204; off-host audit shipping (FND-203). **Defense in depth:** FND-205, FND-207, the
Sessions table's protection, `x-frame-options`.

**Required regression tests:** E-104, E-105, E-112, E-113 and E-117 inverted once fixed; the rest kept as they are.

**Residual risk:** the trusted-operator model (accepted); no independent review (DEF-026).

**Evidence that would raise assurance:**
- an independent review;
- a staged deployment, with its proxy, backups and audit shipping, assessed end to end;
- a load test at the limits.

## 16. Final assurance answers (brief §71)

| Question | Answer |
|---|---|
| Canonical resource domains? | §2.2: an item's domain follows its state (D1 one owner, D2 grantees, D3 joint); personal records D1; account and session D5; audit D4 |
| Who owns each private resource? | the member(s) in its owner set; personal records, their member |
| What belongs to the household? | joint items, shared values and plans, membership and display names, request metadata |
| Principals? | P1, P2, P4 (one undivided role), P7, P8; no P3, P5, P6 |
| Which relationships create authority? | OWNS, SHARED_WITH, APPROVES (requests), MEMBER_OF (pages only), OPERATES (everything) |
| Which rights arise from delegation? | VIEW by grant; joint ownership by agreement |
| Can one household access another? | no (E-101) |
| Can a member see another's private resources because they share a household? | no (E-102, E-103) |
| Can an administrator bypass privacy? | there is no administrator |
| Can a recipient expand a grant? | not through the application (E-106); a database writer can (E-112) |
| Inference through aggregates? | no for content (E-102); yes for counts (E-104, E-105) |
| Does revocation terminate access? What latency? | yes; the next request (E-107, E-108) |
| Can ordinary operators read content? Through which paths was that tested? | database: no (E-110), offline guessing aside (FND-202); runtime: yes for signed-in members (E-111); logs: no (E-115) |
| Operator-isolation level? | OP-1 |
| Does customer approval control operator access? | no; there is no such mechanism (REV-111) |
| Can operators approve themselves? | they need no approval; the console's second approval is policy |
| Can elevation scope change after approval? | no elevation exists |
| Is emergency access separate? Who can trigger it? | no; any one operator, recorded |
| Can PostgreSQL bypass privacy? | read: no, except by guessing; write: integrity yes (FND-201) |
| Can IEx/runtime bypass it? | yes (E-111) |
| Can logs? | no (E-115) |
| Can backups? | as the database: offline guessing only (FND-202) |
| Can KMS? | none exists |
| Who has decryption authority? | each member; the server while they're signed in |
| What is the TCB? | §7 |
| Minimum compromise set for content? | any one of runtime, deployment, root, or TLS terminator; or a database copy plus a guessable passphrase |
| Can deployment authority exfiltrate plaintext? | yes |
| Does the report separate ordinary-operator from provider resistance? | yes: neither is claimed beyond the database path |
| Provider credentials least-privileged? Can any integration move money? | none exist; no (E-013) |
| Records with the correct person, account, household? | yes through the application; a database writer can misassociate (FND-201) |
| Privacy in replicas, backups, exports, analytics? | exports yes (E-109); no analytics; backups and replicas don't exist yet |
| Demonstrated / inferred / unknown? | §8 marks each; FND-202's exploitability is inferred; backups, the proxy and infrastructure are unknown |
| Every finding reproducible? | yes: the assessment tests (FND-202 by inspection of the stored format) |
| Which remediation changes an invariant rather than a symptom? | FND-201's signed operation log (DESIGN-002) makes the access state authenticated; FND-202's pepper removes the database-only path to guessing |

**Completion criteria (§72):** met except criterion 4. Sharing and operator access cannot share one delegation
model, because the operator has no delegation by decision. Criterion 12 holds: no parallel security model remains
beyond the trusted operator, which is a stated architecture.
