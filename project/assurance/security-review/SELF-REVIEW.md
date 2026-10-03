# Self-review findings (ACT-002, 2026-09-26)

This review was done by the same agent that wrote the code, so it is **not a substitute for yours**.
Severity is our estimate against the threat model. *Fixed* means fixed in commit and covered by a
test that fails without the fix.

| # | Severity | Finding | Disposition |
|---|---|---|---|
| **F-01** | **High** | **The plaintext access state is not authenticated.** Owners, grantees, proposals, member list, and public keys can be edited by T1. | **Partly mitigated (agreements signed since WI-090); design issue open** |
| F-02 | High | Public-key substitution in the file redirects future seals to the attacker | **Fixed** for vaults created after WI-020 (pins) |
| F-03 | Medium | Rolling back to an earlier copy of the whole file is undetectable | Open |
| F-04 | Medium | PBKDF2-SHA256 is weak against offline GPU guessing of weak passphrases | Open (recommend Argon2id) |
| F-05 | Medium | Keys stay in BEAM memory while a session is unlocked, with no zeroization | Open (inherent) |
| F-06 | Low | The vault file was created world-readable (0644) | **Fixed** (0600) |
| F-07 | Medium | An Erlang crash dump would write memory, including keys, to disk | **Mitigated** (warning; run with `ERL_CRASH_DUMP_SECONDS=0`) |
| F-08 | Low | Deletion is not secure erasure (filesystem remnants, backups, git) | Documented |
| F-09 | Low | No rate limit on `/login` | Accepted (PBKDF2 cost; offline attack is easier) |
| F-10 | Low | Crafted terms in the file could crash decoding (denial of service) | Accepted; `[:safe]` prevents atom exhaustion |
| F-11 | Info | Metadata stored in plaintext by design | Documented (ASM-020) |
| F-12 | Info | No key rotation on revocation, because items are immutable | Documented (ASM-021) |
| F-13 | Low | A low-order X25519 key in the file makes `compute_key` raise (denial of service) | Mitigated by pins |
| F-14 | Info | Web defences in place and tested | See DESIGN |
| F-15 | Low | KEK and personal key reused with random 96-bit nonces | Accepted at prototype scale |
| F-16 | Low | Two servers on one file: last writer wins | **Fixed**, apart from a millisecond race (WI-026): a change is refused if another process wrote first |
| F-17 | Info | The JSON export is written unencrypted where the user saves it | By design (user's choice) |
| F-18 | Info | Two real bugs were found by the project owner, not by tests | Fixed; shows test-gap risk |

## F-01: unauthenticated access state (the main issue)

**Problem.** Access control is enforced by the `core/` rules running on the file's plaintext
structure, and that structure has no MAC or signature. T1 (a household member with file access) can:

1. **Add themselves as a reader.** They get no key directly. **Before the fix**, though, the next
   time an honest owner saved any change to that item, their session sealed the item key to every
   listed reader, including the attacker. *Confirmed by test before the fix.*
2. **Add themselves as an owner.** The same key leak applies, plus history entries, plus the power
   to act as an owner in their own session (for example, granting others).
3. **Forge proposals and consents.** For example, "Let Cy see *Rent*, agreed so far: Ben" shown to
   Ana. If Ana agrees, the grant applies *through her own legitimate operation*.
4. **Remove people** from owner or grantee lists, delete proposals, or reorder members. These are
   integrity and availability attacks.

**Mitigations in place (WI-020):**
- **No key for a reader who appeared without one.** A session seals item keys and history entries
  only to readers **that session itself added**. A reader present in the loaded file without a key
  can only have got there by editing the file, since every legitimate addition is saved together
  with its key, so they are never given one (`session.ex`, `encrypt_item/4`,
  `baseline_readers/2`). This blocks attacks 1 and 2 on the key-leak path.
  - Tests: `test/tamper_test.exs`, three cases.
  - Mutation checks: 3/3 detected.
  - A 500-sequence model test confirms legitimate flows are unaffected and raise **no false alarms**.
- **Detection.** `Session.integrity_issues/1` reports readers without keys, owners unable to open
  history, references to unknown members, and changed public keys. The interface shows a warning
  banner when any are present.

**Residual risk (open):**
- **Forged consents (attack 3).** The victim's own operation applies the change, so it looks
  legitimate. Detecting it needs authenticated consents.
- **Removals and denial of service (attack 4).**
- **Attacks that avoid the heuristics.** A real owner (who holds the keys) can edit the plaintext
  and re-seal consistently. For example, a co-owner could add a grantee without the other owners'
  consent, bypassing REQ-103.
- **Legacy vaults.** Vaults created before WI-020 have no pins, so F-02 applies to them. The project
  owner's `demo.vault` is one; recreate it.

**Design options we'd like your view on:**
- **(a) A signed operation log.** Each member has an Ed25519 signing key (pinned like the X25519
  keys). Every state change is an operation signed by its actor, and consents are signed too. The
  access state is *derived* by replaying the log through `core/` rules, which rejects operations
  whose signer wasn't entitled. This closes attacks 1–4, except deletion and rollback.
- **(b) Owner-authenticated access state per item.** A MAC over `{owners, grantees}` under a key
  sealed to the owners only. Simpler, but grantees can't verify it, and any single owner can still
  forge it.
- **(c) Accept the residual risk for this study,** with consent wording that states it. Participants
  with safety concerns are already excluded.

## F-02: public-key substitution

T1 replaces Ben's `pub` in the file with their own. Honest members then seal Ben's keys to T1.
**Fix:** at setup, every member's encrypted secret stores `pins` (every member's public key). Seals
use the pinned key, a mismatch is reported to every member at login, and each member's own pinned
key is used for their own decryption. Tests: `tamper_test.exs`, two cases; mutations 2/2 detected.
**Limit:** vaults created before this fix have no pins.

## F-03: rollback

Replacing the file with an older copy restores revoked grants, deleted items, and earlier owner sets,
and nothing in the file can reveal it. Detection would need state held outside the file: for
example, each member's secret storing the last generation they saw, which works only while that
member keeps using the same file. Open.

## F-04: passphrase key derivation

PBKDF2-HMAC-SHA256 at 600,000 iterations (the OWASP 2023 figure) resists casual guessing, but a T1
who copies the file can guess offline with GPUs. There's a 12-character minimum and no strength
check. Recommendation: Argon2id (memory-hard), which needs a NIF dependency outside `:crypto`, plus
a strength estimate at setup. Open.

## F-05 and F-07: keys in memory

An unlocked session holds the member's private key, personal key, and item and entry keys in BEAM
process memory, which can't be reliably zeroized, and the OS may swap it out. A crash dump would
write it to disk. The `serve` task warns unless `ERL_CRASH_DUMP_SECONDS=0` is set. The rest is
inherent to the platform and bounded by the 15-minute idle lock.

## F-15: nonce reuse bound

The KEK only ever encrypts one secret (written once, at setup). The personal key encrypts the
member's personal record once per save, with a fresh random 96-bit nonce. The collision risk stays
far below 2⁻³² for fewer than about 2³² saves, which is far beyond study scale.

## F-16: two servers on one file

**Before WI-026**, each running copy held the vault in memory and wrote it back whole, so a
second copy's save silently replaced the first's changes. Both also used the same temporary file
name.

**Now** the Store remembers a SHA-256 fingerprint of the file it last read or wrote. Before every
change it compares the file on disk. If another process wrote it, the change is refused with a
plain message ("Nothing was saved, so nothing was lost"), the Store reloads, and the member sees
the latest version and can try again. Page reads pick up outside changes too. Temporary files have
random names. Tests cover two Stores on one file in both directions, reads, consecutive writes,
and 20 simultaneous writers.

**What remains:** a narrow window between the check and the rename. Two copies saving within the
same few milliseconds could still lose one change. A lock held for the whole check-and-write would
close it. This is out of scope while one household runs one copy, and the reloaded file still
passes through the WI-020 integrity checks.

## F-18: bugs found by the owner, not by tests

1. The setup task crashed, because `:io.get_password/0` is unsupported under `mix` (WI-015).
2. A vault holding pending proposals couldn't be reopened in a fresh process, because `[:safe]`
   refuses atoms not yet loaded (WI-016).

Both are fixed, with tests that fail without the fix. WI-028 adds an end-to-end test that runs the
real server as its own OS process and uses it over loopback HTTP (unlock, add, share, lock, restart),
and checks from the operating system that it listens on 127.0.0.1 only. They show that our testing had gaps at the
level of the process and the real environment. Please weigh that in how much you rely on the
evidence in EVIDENCE.md.

## WI-079 update (ASSESS-001, 2026-09-30)

ASSESS-001 (see ASSESS-001-implementation-assessment.md), also by ACT-002 and so also not independent, found that
the F-01 mitigation could be bypassed by planting any key entry for the attacker (FND-01: balance readings and new
history leaked, with no lasting warning), that sealed records could be forged by anyone with public keys (FND-04),
and that F-10's `[:safe]` decoding still accepted function terms (FND-02). WI-079 adds signed records and verified
seals (DESIGN.md, WI-079 additions; REQ-192) and non-executable decoding with a shape check. **Still open (DEF-028):**
forged consents and removals (F-01 attacks 3 and 4), rollback (F-03), wholesale replacement of an item by a listed
owner, a grantee vouching a third party onto the latest reading, and tampering done before a member's first
upgraded unlock (trusted once, by that member).

## WI-080 update (2026-10-01)

WI-079's rule that anyone who ever owned an item may write its details and balances was weaker than ASSESS-001
recommended (a former co-owner could add a balance others accepted); WI-080 requires an owner at the time of
writing. Vaults made before signing are now refused, which removes the trust-once window. Still open (DEF-028):
forged consents and removals, rollback, wholesale replacement of an item by a listed owner, and a grantee
vouching a third party onto the latest reading.

## WI-090 update (2026-10-03)

DEF-028 was reproduced at runtime on v0.8.4-alpha (a co-owner wrote the other owner's agreement into the file and
shared a joint item; the cooling-off was no defence). WI-090 signs each agreement with its member's key and counts
only verified ones; the cooling-off's end comes from the signed times (DESIGN.md, WI-088 and WI-090 changes). This
closes F-01 attack 3 (forged consents) as an interim fix ahead of DESIGN-002. Still open (DEF-028): removals (attack
4), an unauthenticated request and proposer, rollback (F-03), wholesale replacement of an item by a listed owner, and
a grantee vouching a third party onto the latest reading.

