# Cryptographic design

Every primitive comes from Erlang `:crypto`, backed by OpenSSL 3.5. No primitive is implemented in
this code. HKDF is composed from HMAC and checked against RFC 5869 test case 1.

## Key hierarchy

```
passphrase ──PBKDF2-HMAC-SHA256 (600,000 iterations, 16-byte random salt)──► KEK (per member)
KEK ──AES-256-GCM──► member secret = { X25519 private key, personal key (32 bytes), pins }
                     pins = { member ⇒ X25519 public key }, for every member, fixed at setup

item key (random, 32 bytes)  ──AES-256-GCM──► item content (attributes)
item key ──seal──► each current reader (owners, grantees, approved prospective joiners)

entry key (random, one per history entry) ──AES-256-GCM──► history entry
entry key ──seal──► each current owner (and approved prospective joiners)

personal key ──AES-256-GCM──► the member's links and deletion records
```

**Seal** (`Crypto.seal/3`): an ephemeral X25519 key pair; the shared secret from ECDH with the
recipient's public key; key = HKDF-SHA256(ikm = shared, salt = eph_pub ‖ recipient_pub,
info = "findependence seal v1", 32 bytes); then AES-256-GCM. The output is
`{eph_pub, nonce, ciphertext, tag}`.

**Associated data** binds every box to its place: `term_to_binary({household_id, context})`, where
context is `{:member, m}`, `{:content, item}`, `{:item_key, item, recipient}`,
`{:entry, item, seq}`, `{:entry_key, item, seq, recipient}`, or `{:personal, m}`.
`household_id` is 16 random bytes per vault. So a box can't be moved between items, recipients,
entries, or vaults without failing authentication.

**Nonces** are 96-bit random values for every encryption. Item content, history entries, and seals
each use a fresh key per box. The personal key and the KEK are reused across saves with a random
nonce each time (see F-15).

## File format (`term_to_binary`, decoded with `binary_to_term(..., [:safe])`)

```
%{v: 1, hid, iterations, unsafe_test,                    # unauthenticated
  members: %{m => %{salt, pub, secret: box}},             # pub is unauthenticated; pinned inside secrets
  member_order: [m],
  items: %{id => %{owners: [m], grantees: [m],             # unauthenticated access state (F-01)
                   content: box, keys: %{m => sealed},
                   ledger: [%{seq, box, keys: %{m => sealed}}]}},
  proposals: %{n => %{item_id, change, consents, proposed_by}},   # unauthenticated (F-01)
  next_proposal,
  personal: %{m => box}}
```

The file is written atomically (temporary file, then rename) with mode 0600.

## Operation flow

All household rules (who may grant, consent, relinquish, and so on) live in the pure `core/`
library. A **session** works as follows:

1. **open**: derive the KEK and decrypt the member's secret. Use the **pinned** public keys, never
   the file's. Decrypt every item key, history entry, and personal record the member can open.
   Items they can't open become placeholders. Compute integrity issues.
2. **act**: run a `core/` operation on the member's decrypted view.
3. **save**: re-encrypt. For each item the member can read, seal the item key to exactly the new
   readers and the history entries to exactly the owners. Keys already present are kept. **A key is
   sealed only to a reader this session added**: a reader listed in the loaded file without a key
   is never given one (F-01 mitigation). Items the member can't read must be unchanged, otherwise
   `save` raises.
4. The **Store** serializes saves: before each operation it refreshes the session from the latest
   file, so members taking turns don't overwrite each other. It also keeps a SHA-256 fingerprint of
   the file it last read or wrote. If another process changed the file, the Store reloads it, and a
   change in flight is refused ("Nothing was saved") rather than overwriting it (F-16, WI-026).
   Temporary files have random names. A millisecond window between the check and the rename remains.

**Presealing (REQ-115).** Once every current owner has agreed to add someone to a shared value, that
person is sealed the item key and history, so they can see what they're being invited into. If the
invitation is withdrawn, the next save removes those seals.

## Interface security (`web.ex`)

- Bandit binds `{127, 0, 0, 1}`.
- A Host check allows only `127.0.0.1:<port>` or `localhost:<port>`, and answers anything else
  with 421. This defends against DNS rebinding.
- `Plug.CSRFProtection` guards every POST.
- The session cookie is signed, `SameSite=Strict`, and `HttpOnly`. It holds only a random 192-bit
  token. Unlocked keys stay in server memory (`Sessions`) and are dropped on logout, on a new login,
  or after 15 minutes idle.
- `secret_key_base` is random per server start.
- Every response carries `Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline';
  form-action 'self'; base-uri 'none'; frame-ancestors 'none'`, plus no-store, nosniff, DENY, and
  no-referrer.
- All user text is HTML-escaped, and the pages contain no JavaScript.

## WI-079 additions (REQ-192; ASSESS-001 FND-01, FND-02, FND-04)

Added after ASSESS-001; the text above describes the design before it and is kept.

- **Signing keys.** Each member's Ed25519 signing key is derived, never stored: seed = HKDF-SHA256(ikm = the
  member's X25519 private key, salt = "", info = "findependence signing v1", 32 bytes). The public key is
  published (local: `members[m].sign_pub`, and a `signers` map kept for members who left; hosted:
  `accounts.signing_public_key`) and pinned like the X25519 keys (local: `sign_pins` in the member's encrypted
  secret; hosted: in the pins record). A published key that differs from the pin is reported
  (`{:signing_key_changed, m}`); verification always uses the pin.
- **What is signed.** Every content box, history entry, and reading written carries its author's id and an
  Ed25519 signature over `term_to_binary({hid, context, author, nonce <> tag <> ciphertext})`, the context being
  the box's associated-data context. Building a view checks the signature under the author's pin and that the
  author was entitled (history replayed in order: the signer is in the entry's `by` and was an owner before it,
  with the exceptions for creation, joining owners, and a departing grantee; content and readings by an owner
  now or earlier). Failures are reported (`{:unsigned_box, ...}`, `{:bad_signature, ...}`,
  `{:signer_not_entitled, ...}`) and the box isn't shown as genuine.
- **Seal commitments.** Each seal carries HMAC-SHA256(sealed key, "findependence seal-commit v1" <>
  term_to_binary(recipient)). A reader present in the loaded state is given new keys only if the saving member
  can vouch for their existing seal (the commitment verifies under the key held, or the seal is in the member's
  legacy record); otherwise `{:unverified_seal, item, member}` is reported, for as long as the seal stays.
- **Legacy record (local).** At a member's first unlock after the upgrade, hashes of every unsigned box and
  uncommitted seal then in the file are stored in that member's encrypted secret; those are shown as written
  before signing without alarm. Anything unsigned or uncommitted added afterwards is reported.
- **Decoding.** `Envelope.decode/1` refuses any function, pid, port, or reference after `binary_to_term(bin,
  [:safe])`, and `Vault.read!/1` checks the whole vault's shape before use.
