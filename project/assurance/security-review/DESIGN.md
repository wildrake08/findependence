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
   file, so members taking turns don't overwrite each other.

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
