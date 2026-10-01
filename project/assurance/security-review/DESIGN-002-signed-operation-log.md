# DESIGN-002: a signed operation log for the household's shared state

**Status:** proposed (CP-027), for ACT-001's decision and for the independent reviewer (DEF-026) to review
**before** it is built. Nothing here is implemented.
**Addresses:** DEF-028 (SELF-REVIEW F-01, attacks 3 and 4; F-03), and the residual risks WI-079..WI-081 recorded.
**Applies to:** the local-first form's vault (the primary case) and the hosted form's rows (the same envelope).
**Scope (REV-113, CP-028 D3, 2026-10-01):** both forms are in scope for the review and for one build, which closes
DEF-028 and DEF-077 (ASSESS-002 FND-201) together. Until then the hosted form carries WI-085's interim code over
each household's records under a server key (REQ-198), which stops whoever can write only the database but not
the operator or a whole-household rollback; whether to keep it as a second layer afterwards is a question for the
reviewer (section 7).

## 1. The problem, precisely

The vault holds two kinds of data:

- **Encrypted records**: each item's content, history entries, and balance readings (sealed per reader, signed by
  their author since WI-079), and each member's personal record (links, plans, marks, goals, retirement settings;
  encrypted under a key only that member holds).
- **Plaintext access state**: the member list, each item's owners and grantees, and pending proposals with their
  agreements (ASM-020). The `core/` rules decide what is allowed, but they run on this state as read from the file,
  and nothing authenticates it.

Someone who can edit the file (T1, the threat model's primary adversary) can therefore still:

| Attack | Today |
|---|---|
| A1. Forge an agreement ("Ben agreed") so an honest member's own action completes a grant or ownership change | Not detected |
| A2. Remove a member from an item's owners or grantees, or delete a proposal | Not detected |
| A3. List themselves as an owner, then write content or balances others accept as an owner's | Partly (WI-080: only an owner when written counts, but the history that says who was an owner is itself editable by a listed owner) |
| A4. A grantee who holds an item key vouches a third person onto the latest balance | Not detected |
| A5. Replace an item wholesale (new key, content, seals) as a listed owner | Not detected |
| A6. Roll the whole file back to an earlier copy (F-03) | Not detected |

Signatures on records (REQ-192) say who wrote a record; they don't say whether that person was allowed to change
who may read it. The fix is to stop storing the access state at all, and derive it.

## 2. Design

### 2.1 Genesis

At setup, every member signs one **genesis record**:

```
genesis = {v: 2, hid, created_at, members: [{id, x25519_pub, ed25519_pub}], iterations}
```

Each member's signature over `hash(genesis)` is stored with it. A vault opens only if every listed member's
signature verifies. This replaces trust-on-first-use pinning (WI-079): every member's keys are fixed and signed by
everyone at the start. The household's membership never changes after setup except by a signed `leave` operation
(nobody can join after setup, ASM-022; CP-009's joining design would add a `join` operation that every current
member signs).

### 2.2 Operations

Every change to the shared state is an **operation**:

```
op = {seq, prev, actor, kind, args, at}
signed = op ++ {sig: Ed25519(actor's key, "findependence op v1" || canonical_encoding(op))}
```

- `seq` counts from 1; `prev` is the hash of the previous signed operation (genesis for the first), so the log is
  a hash chain: nothing can be inserted, reordered, or dropped from the middle without breaking it.
- `kind` and `args` name exactly one `core/` operation and its arguments: `add_item` (with its kind: money item,
  value, account, debt, or shared plan), `propose_owners`, `propose_grant`, `revoke_grant`, `consent`, `withdraw`,
  `relinquish`, `delete`, `leave`, `add_reading`, and `bring_in` (a batch of the above, signed once).
- `args` refer to encrypted records by **hash**, never by content: `add_item` names the hash of the item's signed
  content box; `add_reading` the hash of the reading's box. The access-relevant arguments (owners, grantee,
  proposal number) are plaintext, as today (ASM-020): this design authenticates metadata; it does not hide it.
- **An agreement is its own operation** (`consent`), signed by the member who agrees, naming the proposal by the
  hash of the operation that made it. Nobody can agree on someone else's behalf.
- Canonical encoding: a fixed, versioned binary encoding (not `term_to_binary`, whose output is not guaranteed
  stable across OTP versions), so signatures stay verifiable.

### 2.3 Deriving the state

Opening a vault **replays** the log from genesis through the `core/` rules, which are already pure functions:

1. Check the chain: each `prev` equals the hash of the operation before it; `seq` has no gaps.
2. For each operation, check the signature under the actor's genesis key, then apply it with the core rule as that
   actor. If the rule refuses (`{:error, reason}`), the operation is **rejected**: it changes nothing, and the
   member's view reports it (`{:rejected_operation, seq, reason}`).
3. The resulting `Household` *is* the access state. Owners, grantees, proposals, and agreements stored anywhere
   else are ignored.

What this closes:

- **A1**: an agreement needs the agreeing member's signature.
- **A2**: removals happen only through operations the rules allow (relinquish one's own ownership, leave, an
  ownership change all owners agreed to).
- **A3, A5**: who owns an item at each point comes from signed, rule-checked operations; content is fixed by the
  hash in `add_item`, and there is no operation that replaces it (items are immutable, ASM-021).
- **A4**: keys are sealed to exactly the readers the replayed state contains; a seal to anyone else is ignored and
  reported. Seal commitments (WI-079) stay, as a check that a seal is of the right key.

History entries (the ledger) become **derived** from the operations too, so the record of who did what can't
disagree with what was done.

### 2.4 Encrypted records stay as they are

Content, readings, history entry keys, and seals keep WI-079's format (AES-256-GCM, sealed per reader, signed by
the author, with commitments). The log adds authenticated *structure* on top; it doesn't replace the encryption.
A box is accepted only if an operation in the log names its hash.

### 2.5 Rollback (F-03): detection, with stated limits

Each member's **checkpoint** is the `seq` and hash of the last operation they saw, kept in their encrypted secret
and updated at each of their saves. At unlock, the log must contain that operation at that position; otherwise the
member is told the file was rolled back or replaced ("This household file is older than the one you last used").

**Limit (to state in the threat model and the consent wording):** on one shared device account, the secret lives
in the same file, so restoring a whole old copy of the file restores the old checkpoint too. In-file anchors can't
detect a whole-file rollback. What can:

- **A visible counter.** At unlock: "Last change: #57, Tuesday 3 p.m., by you". A member who sees the number go
  backwards can tell. Cheap; depends on people noticing.
- **An outside checkpoint.** An optional short code (e.g. 8 characters from the checkpoint hash) the member can
  write down or keep on their phone; the app checks it if entered. Strong for those who use it.
- **Separate device accounts** per member (out of the current model, CP-006 B), which puts each member's
  checkpoint out of the others' reach.

Recommendation: the in-file checkpoint and the visible counter in the first version; the outside checkpoint as an
option if the reviewer thinks it worth its cost.

### 2.6 What the log does not do

- **Deletion and corruption** of the file (availability) stay out of scope (THREAT-MODEL non-goal).
- **Metadata** stays visible to members and to anyone with the file (ASM-020): the operations name owners and
  grantees in plaintext.
- **Coercion**: a member pressured into signing (agreeing) has still signed (DEF-016).
- **Personal records** (links, plans, goals) are already authenticated by their AEAD under the member's own key;
  they can be rolled back with the file, as above, but not forged.
- **The hosted operator** can still withhold operations or serve an old database, and reads members' data while
  they are signed in (CP-024). Members' checkpoints narrow what the operator could replay unnoticed.

## 3. The hosted form

The same log is stored as rows (`operations: household_id, seq, prev, actor, kind, args, sig`), with the chain and
signatures checked on load exactly as locally. The hosted form's member list changes by invitation (REQ-185), so it
needs a signed `join` operation (the inviter's signature on the joiner's keys, then the joiner's own) in place of
fixed genesis membership; that is the part to design with the reviewer, since the operator relays the keys.

## 4. Cost and performance

- Opening a vault replays the log. Per operation: one Ed25519 verification and one pure rule. A household with
  2,000 items and 10,000 operations needs about 10,000 verifications (tens of milliseconds) plus the rules. Pages
  already re-read the vault; WI-082 measured 41.9 ms at 200 items against a 50 ms budget, so the replay result must
  be cached per process and rebuilt only when the file changes (the Store already fingerprints it). If logs grow
  large, **signed snapshots** (all members' signatures on a state hash at a sequence number) can shorten replay;
  not needed for the study's scale.
- File size grows by roughly 200 bytes per operation.

## 5. Migration

None needed for testers: v0.8.2 already requires a new household, and the format would become `v: 2` (today's
vaults are `v: 1`), refused by
older versions and refusing older files with the same message. The hosted form is not in service.

## 6. Tests the implementation must have

Each must fail without the mechanism (planted-and-restored):

1. A forged agreement (signed by the wrong member, or unsigned) is rejected and reported; the honest member's own
   agreement completes nothing it shouldn't.
2. An owner or grantee removed by editing the state has no effect; the replayed state still lists them.
3. Operations reordered, dropped from the middle, or inserted break the chain and are reported.
4. A listed-but-not-entitled owner's content or balance is rejected (A3); there is no way to replace an item (A5).
5. A seal to a reader the replay doesn't contain is ignored and reported (A4).
6. A truncated log (operations dropped from the end) is detected by the member whose checkpoint is past the end.
7. The visible counter appears at unlock and goes backwards after a whole-file rollback (a test that documents the
   limit, not one that claims prevention).
8. A model test: 500 random honest sequences replay to exactly the state the operations produced, with no false
   alarms (as today's model test).
9. Genesis: a vault whose genesis lacks a member's valid signature is refused.

## 7. Questions for the reviewer

1. Is replay-derived state, with rule-rejected operations reported and skipped, the right semantics, or should one
   rejected operation make the whole log untrusted?
2. Canonical encoding: is a hand-specified binary encoding preferable to a standard one (e.g. deterministic CBOR)?
3. Rollback: is the visible counter enough for the study, or should the outside checkpoint ship first?
4. The hosted `join` operation: what should the inviter sign, and how should the joiner verify the household's
   genesis and members' keys when the operator relays them?
5. Is signing the agreement to a proposal by the proposal operation's hash enough to prevent replaying an agreement
   onto a later, different proposal?

## 8. Work, if adopted

One WorkItem for the local form (format v2, genesis, operations, replay, checkpoint and counter, the tests above),
and one for the hosted form (operation rows, signed join). Estimated as the largest change since WI-011, because
every save path changes from "write the new state" to "append operations"; the `core/` rules themselves don't
change.
