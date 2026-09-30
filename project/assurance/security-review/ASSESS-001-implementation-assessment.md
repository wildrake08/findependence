# ASSESS-001: implementation-level security and privacy assessment of v0.8.1-alpha

**Assessed:** main at 25508aa (v0.8.1-alpha), 2026-09-30, by ACT-002 with three delegated review strands.
**Not independent.** The same AI system family wrote the code. This assessment adds evidence for the review GATE-016
asks for; it does not discharge GATE-016 `1_security_review` or DEF-026.

**How:** source review of app/, core/, shared/, hosted/; runtime testing of the hosted form (a copy of the released
tree on 127.0.0.1 with a throwaway database) and of the local form (scratch copies); scans of logs and a full
database dump; tamper experiments on real vault files; `mix hex.audit`, sobelow, and a secrets search of the tree and
all 298 revisions. The full report, with matrices, data-flow register, threat model, and evidence index, was published
to ACT-001; the machine-readable findings are in [ASSESS-001-findings.json](ASSESS-001-findings.json).

**Not applicable, on evidence:** no financial-data aggregator, OAuth, webhook, provider token, email, card data, or
money movement exists in the code or its dependencies.

**Held at runtime:** household isolation (13 kinds of cross-household action refused, rows unchanged); leaving ends
every other session at once; sign-out and passphrase change end sessions on the server; CSRF and one-time form
tokens; no open redirect; output escaping; hostile import files refused; no item names, amounts, addresses, or
passphrases in the hosted log or database.

## Findings and their mitigation (WI-079)

| Finding | Severity | Status | Form | Title | Mitigation |
|---|---|---|---|---|---|
| FND-01 | HIGH | CONFIRMED | local | A planted key entry makes an honest save hand balance readings and new history entries to a member who edited the vault file | WI-079 strand A: seal commitments; extended only to vouched readers |
| FND-02 | HIGH | LIKELY | local (vault file); hosted (database columns) | Stored bytes are decoded with binary_to_term [:safe], which still accepts function terms, and the decoded vault is not shape-checked | WI-079 strand A: decode refuses functions, pids, ports, references; vault shape checked |
| FND-03 | HIGH | CONFIRMED | hosted (not in service) | A recovery key never expires, cannot be replaced, and still works after the owner changes their passphrase | WI-079: replace the key (REQ-184 AC-5); recovery replaces the used key (AC-6) |
| FND-04 | MEDIUM | CONFIRMED | local | Item content and history entries can be forged by anyone holding only public keys | WI-079 strand A: Ed25519 signatures on content, entries, readings; legacy record |
| FND-05 | MEDIUM | CONFIRMED | local | Crashes write decrypted household data, and a malformed sign-in the typed passphrase, to the console log | WI-079: param shapes refused (400); crash details withheld from the log; login without fields refused |
| FND-06 | MEDIUM | CONFIRMED | hosted | Anyone who knows a member's address can keep them locked out, and sign-up reveals which addresses have accounts | WI-079: limits per address and client (10), client (30), address total (100); sign-ups 10 per client (REQ-190 AC-1, AC-5) |
| FND-07 | MEDIUM | CONFIRMED | hosted | One invitation code admits several people when redeemed concurrently | WI-079: code claimed inside the transaction |
| FND-08 | MEDIUM | CONFIRMED | hosted | A leftover consent row stops a member who owns nothing from leaving or deleting their account | WI-079: leaving withdraws the leaver's agreements and own proposals (core) |
| FND-09 | MEDIUM | LIKELY | hosted (deployment-dependent) | Attempt limits are keyed on the connection's address, so behind the required reverse proxy every visitor shares one counter | WI-079: client from X-Forwarded-For only behind TRUSTED_PROXIES |
| FND-10 | MEDIUM | CONFIRMED | hosted | Every page loads and decodes the whole household, and nothing bounds a household's size | WI-079: at most 2,000 items per household (REQ-190 AC-4) |
| FND-11 | LOW | CONFIRMED | both | The relinquish confirmation names the owners of an item the member cannot see | WI-079: co_owners only for an owner (both forms) |
| FND-12 | LOW | CONFIRMED | hosted (parameter shapes: both) | Refusals from pages other than home, and unexpected parameter shapes, crash with 500 | WI-079: put_view in render_home; param shapes refused (400) |
| FND-13 | LOW | CONFIRMED | hosted (deployment-dependent; MEDIUM if the database is off-host) | Production database settings: no TLS, one owner role for migrations and runtime, audit table writable | WI-079: verified TLS to the database unless it is on loopback; audit_events append-only trigger; role split documented as a deployment step |
| FND-14 | LOW | CONFIRMED | hosted (the local form sends no-store) | Hosted signed-in pages and the export download may be kept in the browser cache | WI-079: no-store on every browser-pipeline response |
| FND-15 | LOW | CONFIRMED | local | Local flash messages carrying item names travel in a signed but unencrypted cookie | WI-079: session cookie encrypted |
| FND-16 | LOW | CONFIRMED | local | Local 421 and 500 responses lack the security headers | WI-079: headers before the Host check |
| FND-17 | LOW | CONFIRMED | local | A malformed vault file, or a few crashing requests, stop the local server | WI-079: store keeps the last readable copy; changes refused while unreadable; unreadable at start stops with a message |
| FND-18 | LOW | CONFIRMED | hosted (build output) | The built release's distribution cookie is world-readable | WI-079: RELEASE_COOKIE required at run time (32+ characters); cookie file 0600 |
| FND-19 | LOW | CONFIRMED | hosted | Hosted sessions have no absolute lifetime and are node-local | WI-079: sessions end 12 hours after sign-in |
| FND-20 | LOW | CONFIRMED | hosted | Production configuration accepts a default host and an unchecked email-hash key | WI-079: PHX_HOST required; EMAIL_HMAC_KEY Base64 of 32+ bytes |
| FND-21 | INFO | CONFIRMED | both | Smaller hardening items | WI-079: /specimen not routed in production; Permissions-Policy; form-token tables swept daily; private upload directory (local); Tailwind binary SHA-256 pinned (container image digests not pinned) |
| FND-22 | INFO | CONFIRMED | hosted (by design, disclosed) | The hosted operator can read what signed-in members can read | CP-024 opened (no code change, REV-106) |

Each finding's Defeater is DEF-064..DEF-076 (FND-13..FND-21 share DEF-076). Residual risks after WI-079 are recorded
in WI-079 and in SELF-REVIEW.md.
