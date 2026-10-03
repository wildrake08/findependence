# Findependence prototype: security review brief

**For:** an independent reviewer with applied-cryptography and application-security experience.
**Status:** a research prototype, not a security product. **It has not been independently reviewed**, and that
review is a precondition for any household using it (DEF-026, GATE-016 `1_security_review`). Nobody uses it with
real information today: testers use made-up data only.
**Code under review:** the repository's `main` at the commit this brief arrives with (the tag or commit we send),
which includes v0.8.5-alpha's local form and the hosted form after WI-085, WI-086, WI-088, and WI-090 (tag
`review-3`).

## The system in brief

Findependence is a household finance system: members record money in and out, accounts and debts, and what they
value, and see what's coming up and plan ahead. Each member's information is encrypted separately and shared only
by their choice; joint decisions need every owner's agreement; anyone can take their own record and leave. It
never gives advice and moves no money. It comes in two forms:

- **Local-first** (released as v0.8.5-alpha to testers): one household device, one encrypted vault file, a browser
  interface on 127.0.0.1 only, no outbound connections. **This is the form the study (STUDY-001) would use.**
- **Hosted** (complete, not in service): a server-rendered web application on PostgreSQL. **The operator is trusted
  by decision** (REV-111): the server holds a signed-in member's unwrapped key, so the operator could read what they
  can read, and members are told this before they sign up (REQ-180). It is offered to no one until its own
  security, legal, and ethics reviews pass.

Both forms share one envelope (sealing, signing, integrity checks) and one set of household rules.

## What we're asking

1. **Is the design sound for its stated threat model** ([THREAT-MODEL.md](THREAT-MODEL.md))? Where does it fail?
   The central adversary is another member of the same household, including in financial control between partners.
2. **Is the cryptography used correctly** ([DESIGN.md](DESIGN.md))? The primitive choices, key derivation, the
   sealing construction, nonces, associated data, the Ed25519 signatures derived from each member's X25519 key, and
   the seal commitments.
3. **Do our own reviews hold up?** [SELF-REVIEW.md](SELF-REVIEW.md) and two implementation assessments by the same
   AI system that wrote the code ([ASSESS-001](ASSESS-001-implementation-assessment.md),
   [ASSESS-002](ASSESS-002-implementation-assessment.md)). Did we miss anything, mis-rate anything, or call
   something mitigated that isn't? We especially want your view on **F-01**, the unauthenticated access state
   (owners, grantees, requests, agreements): the most serious known issue, only partly mitigated. Agreements
   are now signed (v0.8.5-alpha, REQ-203); the rest is not.
4. **Can the local form responsibly go in front of study participants**, and under what conditions? For example,
   study households only, with consent wording that states the remaining limits.
5. **Review DESIGN-002 before it is built** ([DESIGN-002-signed-operation-log.md](DESIGN-002-signed-operation-log.md)).
   ACT-001 chose it (REV-109, CP-027) to close what remains of F-01: a signed, hash-chained operation log from which
   the household's access state is derived by replaying the household rules. Its section 7 lists five questions;
   your answers decide what is built. Since REV-113 it covers **both forms**, so please also consider:
   - **a.** In the hosted form the operator relays every operation. What does a signed log protect against when the
     server is trusted with members' keys while they're signed in, and is that worth its cost there?
   - **b.** WI-085 added an interim code over each hosted household's records under a server key (REQ-198, below).
     Should it stay as a second layer once DESIGN-002 is built, or go?
6. **The hosted form's own controls**, to the extent you can before it has a deployment:
   - the passphrase key: PBKDF2-HMAC-SHA256 (600,000 iterations) under HMAC-SHA256 with a server-held pepper
     (REQ-197), and the recovery key (160 random bits, HKDF);
   - the household records' code (REQ-198): HMAC-SHA256 over a canonical encoding of everything a household holds,
     checked at every read under a share lock, written at every change; what it does and doesn't stop;
   - request identifiers (REQ-199): HMAC-SHA256 of the household and request number, truncated to 72 bits;
   - keys held in server memory for a session (15 minutes idle, 12 hours at most), and the trusted-operator
     disclosure (REQ-180): is it truthful and sufficient for what the operator can do (ASSESS-002 section 5, 7)?

Everything we know about the prototype's weaknesses is written down. We'd rather hear that it's unsuitable than
have a problem found after participants are using it.

## What we'd like back

- Findings, each with a severity, the affected form, and how to reproduce it or why you believe it.
- An answer to each question above, including DESIGN-002's section 7 and 5a–b.
- For question 4, a clear statement: suitable for the study as is, suitable under named conditions, or not
  suitable; and what would change your answer.
- Anything you'd require before the hosted form is offered to anyone.

We'll record your findings as Defeaters against the design and the code, and your conclusions as the review
GATE-016 requires; nothing you say will be paraphrased into a stronger claim than you made.

## Reading order

| # | Read | For | About |
|---|---|---|---|
| 1 | [THREAT-MODEL.md](THREAT-MODEL.md) | both | assets, adversaries, what is and isn't claimed (written for the local form; the hosted trust model is in 7) |
| 2 | [DESIGN.md](DESIGN.md) | both | key hierarchy, vault format, sealing, each operation's flow, and WI-079/WI-080's changes |
| 3 | [SELF-REVIEW.md](SELF-REVIEW.md) | local | 18 findings with dispositions, and what remains after WI-079..WI-081 |
| 4 | [ASSESS-001](ASSESS-001-implementation-assessment.md) and [findings](ASSESS-001-findings.json) | both | 22 findings at v0.8.1, all mitigated or decided |
| 5 | [ASSESS-002](ASSESS-002-implementation-assessment.md) and [findings](ASSESS-002-findings.json) | hosted | resources, delegation, revocation, operator isolation, the TCB; 8 findings, mitigated by WI-085 except the accepted operator path |
| 6 | [DESIGN-002](DESIGN-002-signed-operation-log.md) | both | the proposed fix for F-01, to review before it is built |
| 7 | [ARCH-004 section 6](../design/ARCH-004-client-architecture-options.md), [OPS-001](../design/OPS-001-hosted-operating-controls.md), [DEPLOY.md](../../../hosted/DEPLOY.md) | hosted | the chosen architecture and trusted-operator model, operating controls, and what a deployment must satisfy |
| — | [EVIDENCE.md](EVIDENCE.md) | both | tests, mutation testing, reproduction, and bugs found so far |

## Known open issues

| Issue | Form | State |
|---|---|---|
| **DEF-028**: someone who can edit the vault file (a member, on the shared device) can remove people, plant or drop a request, and roll the file back. Planted readers get no keys, forged records are refused (WI-079..WI-081), and since v0.8.5 a forged agreement isn't counted (WI-090) | local | open; DESIGN-002 chosen, not built |
| **DEF-077**: the same for the hosted form. Whoever can write only the database can no longer change, forge, or roll back a household's records (REQ-198, REQ-200, WI-085 and WI-086); the operator, who holds the keys, can, except forge an agreement (it lacks members' signing keys, REQ-203 AC-5) | hosted | open; DESIGN-002 |
| **The operator reads signed-in members' information** (ASSESS-002 FND-203): code run in the server can reach session keys; one operator can turn the console on, recorded with an approval reference | hosted | accepted by design (REV-111), disclosed (REQ-180); operator-privacy level OP-1 |
| **Metadata is plaintext** (ASM-020): who is in the household, who owns and can see which item, requests and agreements, item identifiers, display names. In the hosted form, since WI-086, only to the operator: the database holds them encrypted (REQ-200) | local; hosted operator | accepted |
| **Coerced consent can't be detected** (DEF-016). Since v0.8.4, sharing, giving away, and deleting wait 72 hours after the last owner agrees, and anyone whose agreement it rests on can cancel alone (REQ-201, REQ-202) | both | open; study screening and the cooling-off |
| **No secure deletion** on disk (SELF-REVIEW F-08); **no backup** of the local vault (CP-010 A) | local | accepted |
| **Container images not pinned by digest** (needs registry access) | both | open (DEF-076 note) |

## Scope

| In scope | Files |
|---|---|
| Cryptography wrappers | `shared/lib/findependence_shared/crypto.ex` (129 lines) |
| The envelope: a member's view, sealing, opening, signing, commitments, integrity checks (the core of the review) | `shared/lib/findependence_shared/envelope.ex` (1,100 lines; signed agreements since WI-090) |
| Decoding stored bytes to plain data | `shared/lib/findependence_shared/safe_term.ex` |
| Local vault format, creation, key pinning, unlocking | `app/lib/findependence_app/vault.ex`, `session.ex` |
| Local session registry, idle lock, single writer | `app/lib/findependence_app/sessions.ex`, `store.ex` |
| Local web interface and passphrase entry | `app/lib/findependence_app/web.ex`, `web/`, `secret.ex`, `app/lib/mix/tasks/*.ex` |
| Hosted accounts, keys, sessions, attempt limits | `hosted/lib/findependence_hosted/accounts.ex`, `sessions.ex`, `limits.ex`, `common_passphrases.ex` |
| Hosted storage, tenancy, records' code, request identifiers | `hosted/lib/findependence_hosted/domain.ex`, `operation.ex`, `tenancy.ex`, `state_seal.ex`, `request_refs.ex` |
| Hosted web boundary | `hosted/lib/findependence_hosted_web/` (`endpoint.ex`, `router.ex`, `auth.ex`, `form_guard.ex`, `param_shapes.ex`, `security_headers.ex`) |
| Hosted operations | `hosted/lib/findependence_hosted/audit.ex`, `operator_access.ex`, `preflight.ex`, `release.ex`, `db_roles.ex`; `hosted/rel/` |

**Out of scope:** `core/` holds the household rules (who may do what) as pure functions with no cryptography,
though you may want `core/lib/findependence/household.ex` for context. `automation/` and `project/` are
governance tooling.

**Stack:** Elixir 1.20, Erlang/OTP 29, `:crypto` backed by OpenSSL 3.5; no third-party cryptography library.
Local form: Plug with Bandit, no JavaScript, no network client, no remote resources. Hosted form: Phoenix 1.8,
server-rendered pages (no LiveView in production), PostgreSQL 17.

## Running it

Everything runs in the repository's dev container (or any machine with Elixir 1.18+, OTP 27+, and, for the hosted
form, PostgreSQL).

```sh
# tests: core 213, shared 9, local form 650, hosted 505 (needs PostgreSQL; PGHOST, PGUSER, PGPASSWORD)
(cd core && mix test); (cd shared && mix test); (cd app && mix test)
(cd hosted && mix ecto.create && mix test)
(cd hosted && mix test test/assessment --trace)   # ASSESS-002's attacks, each printing its evidence line

# the local form
cd app && mix deps.get
mix findependence.setup ../review.vault Ana Ben Cy        # prompts for each passphrase, 12+ characters
ERL_CRASH_DUMP_SECONDS=0 mix findependence.serve ../review.vault 4000   # then http://localhost:4000

# the hosted form (development settings: no TLS, keys not secret)
cd hosted && mix setup && mix ecto.create && mix ecto.migrate && mix phx.server   # http://localhost:4000
```

**To inspect or tamper with a local vault** (`cd app && iex -S mix`):

```elixir
v = FindependenceApp.Vault.read!("../review.vault")
v.items |> Enum.map(fn {id, r} -> {id, r.owners, r.grantees, Map.keys(r.keys)} end)
v = update_in(v, [:items, "<id>", :grantees], &["<member id>" | &1])   # e.g. attack F-01
FindependenceApp.Vault.write!(v, "../review.vault")
{:ok, s} = FindependenceApp.Session.open(v, "<member id>", "<passphrase>")
FindependenceApp.Session.integrity_issues(s)

# forge an agreement (DEF-028's reproduction, now refused): app/test/def028_forged_agreement_test.exs
v = update_in(v, [:proposals, 1, :consents], &MapSet.put(&1, "<member id>"))
```

The hosted form's equivalent is to change rows in `psql`; since WI-085 the household is then refused until its
code is rewritten (`FindependenceHosted.Domain.seal!/1`, as an operator holding the key could), which is how the
signing and commitment tests in `hosted/test/findependence_hosted/signing_test.exs` exercise the deeper layers.

## Intended future key handling (not built)

Households can't add a member after setup in the local form (ASM-022). CP-009 records the design chosen for later,
so you can review it before it is built: a newcomer enrolls at the device with their own passphrase, which creates
their keys and a request to join; every current member must agree while unlocked, and agreeing pins the
newcomer's public key in that member's secret; a short key fingerprint is shown at enrollment and at agreement; the
newcomer joins with access to nothing, and names are never reused. We would value your view on the window between
enrollment and the last agreement, when the pending public key sits in the file unpinned, and on whether the
fingerprint comparison is worth its cost for members sharing one device. (The hosted form already admits members
by one-time invitation codes, REQ-185; DESIGN-002 question 4 asks how a joiner should verify the household.)

## What changed since this brief was first written

- **v0.8.2-alpha (WI-079..WI-081), from ASSESS-001:** every content box, history entry, and balance is signed by
  its author with a pinned Ed25519 key derived from their X25519 key, and accepted only from an owner at the time
  of writing (REQ-192); seals carry key commitments, so new keys go only to readers whose seal the saver can
  verify; stored bytes decode to plain data only and the vault's shape is checked; vaults made before signing are
  refused. DESIGN.md and SELF-REVIEW.md have WI-079 and WI-080 sections on exactly what changed and what remains.
- **The cryptography moved to `shared/`** (WI-074) so both forms use the same envelope; the local form's
  `vault.ex` and `session.ex` now hold only the file and unlocking.
- **The hosted form** was decided as server-rendered with a trusted operator (REV-111, CP-024 A) and given
  operating controls (OPS-001, WI-084).
- **ASSESS-002 and WI-085 (REV-113)** in the hosted form: the records' code (REQ-198), the passphrase pepper and a
  list of common passphrases refused (REQ-197), request identifiers that don't count (REQ-199), a per-member item
  limit, the sessions table private to its process, audit records copied to the log, the console only with an
  approval reference, an encrypted session cookie. DESIGN-002 now covers both forms.
- **The ASSESS-002 re-run and WI-086 (REV-114), released to testers as v0.8.3-alpha:** nobody becomes an owner of
  any item without agreeing, in both forms (REQ-115; a prospective owner every current owner has agreed to is
  sealed the history and readings before their own agreement, REQ-133 AC-7, REQ-170). In the hosted form each
  household's records are one AES-256-GCM block under a server key, with display names encrypted (REQ-200), and a
  change counter kept outside the database refuses a restored earlier copy (REQ-198 AC-5); a key that doesn't
  match its account is refused (REQ-182 AC-5). Tag `review-2` replaced `review-1`.
- **v0.8.4-alpha (WI-088, REV-115), the cooling-off for coerced consent (DEF-016):** sharing, giving away, and
  deleting wait 72 hours once every current owner has agreed; anyone whose agreement it rests on cancels alone;
  protective changes and leaving are immediate (REQ-201, REQ-202).
- **v0.8.5-alpha (WI-090, REV-116), signed agreements:** DEF-028 was reproduced at runtime (a co-owner forging the
  other's agreement in the file); each agreement is now signed by its member and counted only if it verifies, and
  the cooling-off's end is computed from the signed times (REQ-203; DESIGN.md, WI-088 and WI-090 changes). Tag
  `review-3` replaces `review-2`.

## Context

The prototype holds a household's money items and personal values, and lets each member control who else in the
household can see them. The design's central concern is that **a member's information stays theirs even from
other members of their own household**, including in situations of financial control between partners (PRI-002).
Participants with current safety concerns are screened out of this first study for exactly that reason. The system
should still be judged against that adversary, because it's the one it exists for.
