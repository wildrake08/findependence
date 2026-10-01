# Findependence prototype: security review brief

**For:** an independent reviewer with applied-cryptography and application-security experience.
**Status:** research prototype for a small observational study with 3–5 households (STUDY-001).
It has not been independently reviewed. This review is a precondition for any household using it
(DEF-026).

## What we're asking

1. **Is the design sound for its stated threat model** ([THREAT-MODEL.md](THREAT-MODEL.md))? Where does it fail?
2. **Is the cryptography used correctly** ([DESIGN.md](DESIGN.md))? This covers the primitive choices, key derivation, sealing construction, nonce handling, and associated data.
3. **Do the self-review findings hold up** ([SELF-REVIEW.md](SELF-REVIEW.md))? Did we miss anything? We especially want your view on **F-01**, the unauthenticated plaintext structure. It's the most serious known issue, and only partly mitigated.
4. **Can the prototype responsibly go in front of study participants,** and under what conditions? Examples: study households only, with consent wording that states the remaining limits.

5. **Review DESIGN-002 before it is built** ([DESIGN-002-signed-operation-log.md](DESIGN-002-signed-operation-log.md)).
   ACT-001 chose it (REV-109, CP-027) to close what remains of F-01: a signed, hash-chained operation log from which
   the household's access state is derived by replaying the household rules. Its section 7 lists five questions
   we'd most like answered; your answers decide what is built.

Everything we know about the prototype's weaknesses is written down. We'd rather hear that it's unsuitable than have a problem found after participants are using it.

## Since this brief was first written (v0.8.2-alpha, 2026-10-01)

- **ASSESS-001** ([ASSESS-001-implementation-assessment.md](ASSESS-001-implementation-assessment.md),
  [ASSESS-001-findings.json](ASSESS-001-findings.json)): an implementation-level assessment by the same AI system
  that wrote the code, so **not independent**. It found that the F-01 mitigation could be bypassed by planting any
  key entry (FND-01), that sealed records could be forged with public keys alone (FND-04), and that `[:safe]`
  decoding still accepted functions (FND-02), among 22 findings.
- **WI-079..WI-081** (released in v0.8.2-alpha): every content box, history entry, and balance is signed by its
  author with a pinned Ed25519 key derived from their X25519 key, and accepted only from an owner at the time of
  writing (REQ-192); seals carry key commitments, so new keys go only to readers whose seal the saver can verify;
  stored bytes decode to plain data only and the vault's shape is checked; vaults made before signing are refused.
  DESIGN.md and SELF-REVIEW.md have WI-079 and WI-080 sections describing exactly what changed and what remains.
- **Where the cryptography now lives:** `shared/lib/findependence_shared/crypto.ex` and `envelope.ex` (sealing,
  opening, signing, commitments, integrity checks; used by both forms), `safe_term.ex` (decoding), and
  `app/lib/findependence_app/vault.ex` and `session.ex` (the local file and unlocking). The file list under Scope
  below predates this move.
- **The hosted form** (`hosted/`, not in service) uses the same envelope with PostgreSQL; the operator can read
  what signed-in members can (disclosed; CP-024 is open on whether to change that).
- Test counts below are from the first version of this brief; at v0.8.2-alpha: app 633, core 201, shared 9,
  hosted 445 (REPRO-RUN-023).

## Scope

| In scope | Files |
|---|---|
| Cryptography wrappers | `app/lib/findependence_app/crypto.ex` (about 90 lines) |
| Vault format, creation, key pinning | `app/lib/findependence_app/vault.ex` |
| Per-member session: decrypt, re-seal, integrity checks | `app/lib/findependence_app/session.ex` (the core of the review) |
| Server-side session registry and idle lock | `app/lib/findependence_app/sessions.ex`, `store.ex` |
| Local web interface | `app/lib/findependence_app/web.ex`, `web/html.ex` |
| Passphrase entry | `app/lib/findependence_app/secret.ex`, `app/lib/mix/tasks/*.ex` |

**Out of scope:** `core/` holds the household rules (who may do what), which are pure functions with no cryptography, although you may want to skim `core/lib/findependence/household.ex` for context. `automation/` and `project/` are governance tooling.

**Stack:** Elixir 1.20, Erlang/OTP 29, `:crypto` backed by OpenSSL 3.5, Plug with Bandit for HTTP.
There is no JavaScript, no network client, and no remote resources.

## Running it

```sh
# in the repository's dev container, or any machine with Elixir 1.18+ and OTP 27+
cd app && mix deps.get
mix test                                    # 110 tests, including tamper tests (test/tamper_test.exs) and a real-server test (test/end_to_end_test.exs)
mix findependence.setup ../review.vault Ana Ben Cy   # prompts for each passphrase, 12+ characters
ERL_CRASH_DUMP_SECONDS=0 mix findependence.serve ../review.vault 4000
# then open http://localhost:4000 (loopback only)
```

**To inspect or tamper with a vault from an IEx session** (`cd app && iex -S mix`):

```elixir
v = FindependenceApp.Vault.read!("../review.vault")
v.items |> Map.keys()                         # opaque item ids
v.items |> Enum.map(fn {id, r} -> {id, r.owners, r.grantees, Map.keys(r.keys)} end)
v = update_in(v, [:items, "<id>", :grantees], &["Cy" | &1])   # e.g. attack F-01
FindependenceApp.Vault.write!(v, "../review.vault")
{:ok, s} = FindependenceApp.Session.open(v, "Ana", "<passphrase>")
FindependenceApp.Session.integrity_issues(s)
```

## Intended future key handling (not built)

Households can't add a member after setup today (ASM-022). CP-009 records the design chosen for
later, so you can review it before it is built: a newcomer enrolls at the device with their own
passphrase, which creates their keys and a request to join; every current member must agree while
unlocked, and agreeing pins the newcomer's public key in that member's secret; a short key
fingerprint is shown at enrollment and at agreement; the newcomer joins with access to nothing, and
names are never reused. We would value your view on the window between enrollment and the last
agreement, when the pending public key sits in the file unpinned (the F-01/F-02 threat), and on
whether the fingerprint comparison is worth its cost for members sharing one device.

## Contents

- [THREAT-MODEL.md](THREAT-MODEL.md): assets, adversaries, and what is and isn't claimed.
- [DESIGN.md](DESIGN.md): key hierarchy, file format, sealing, and the flow of each operation.
- [SELF-REVIEW.md](SELF-REVIEW.md): 18 findings, with severity, disposition, and tests.
- [EVIDENCE.md](EVIDENCE.md): tests, mutation testing, reproduction, and bugs found so far.

## Context

The prototype holds a household's money items and personal values, and lets each member control who
else in the household can see them. The design's central concern is that **a member's information
stays theirs even from other members of their own household**, including in situations of financial
control between partners (PRI-002). Participants with current safety concerns are screened out of
this first study for exactly that reason. The system should still be judged against that
adversary, because it's the one it exists for.
