# Threat model

## Setting

- **One shared device** (CP-006 option B, chosen by the project owner). One household uses one
  computer, with **a single OS user account**. Separate OS accounts are not assumed.
- **Local only.** A web server binds to 127.0.0.1. Everything is stored in one vault file, and there
  is no network sync, no cloud storage, and no outbound connections.
- **Fixed membership.** Members are set at creation. Members can leave, but nobody can join.
- **One active session at a time.** A member unlocks with their passphrase. The session locks on
  logout, or after 15 minutes idle.

## Assets

| Asset | Examples | Who should have access |
|---|---|---|
| **A1. Item contents** | "Therapy copay, −120", "Wages +3,200" | Its owners and grantees |
| **A2. Values** | "Not owing anyone" | Its owners and grantees |
| **A3. Links** (item to value) | "Rent → A safe home" | Only the member who made the link |
| **A4. Item history** | Who shared what with whom, and when | The item's owners |
| **A5. Deletion records** | That the member deleted something (never what it was) | Only that member |
| **A6. Access state** | Who owns and who can see each item | Members, but **tampering with it must not lead to access** |
| **A7. Passphrases and private keys** | | Only their member |

**Not protected, by design (ASM-020).** Member names, public keys, opaque item ids, owner and
grantee lists, and the shape of pending proposals are stored in plaintext. Participants are told this.

## Adversaries

| # | Who | Capabilities | In scope? |
|---|---|---|---|
| **T1** | **Another household member** (the primary adversary) | Uses the same device and account. Can read, copy, edit, replace, or delete the vault file at any time, including while others are logged out. Knows their own passphrase. Is technically capable: may use IEx or a hex editor. | **Yes** |
| T2 | Someone who obtains a copy of the file (lost laptop, backup) | Offline access to the file; no passphrases | Yes: confidentiality only |
| T3 | A malicious website visited on the device | Can make the browser send requests to localhost | Yes: CSRF, DNS rebinding |
| T4 | Malware running as the same OS user | Can read memory, log keystrokes, and alter the program | **No**: out of reach for a local app |
| T5 | Another OS user on the same machine | File-system access, depending on permissions | Partly: file mode 0600 (F-06) |
| T6 | Someone observing the screen while a member is logged in | | No: operational; auto-lock only |
| T7 | Loss of the file: the device breaks, is lost, or the file is deleted | Every member loses everything; there is no backup | **No**: availability is accepted as a study limit (CP-010 A); participants are told, and members can save their own export. Restoring an old copy is a rollback (F-03), so ad-hoc copies are not a safe backup |

## Security goals (what we claim to aim for; these are not established claims)

- **G1. Confidentiality against T1 and T2.** A member without access to A1–A5 cannot recover them
  from the file, even with their own secrets and unlimited time, **given a strong passphrase**.
- **G2. Tampering doesn't create access.** A T1 who edits the plaintext structure (A6) must not
  cause an honest member's software to give them keys. *Partly achieved; see SELF-REVIEW F-01.*
- **G3. Tampering is visible.** Edits to A6 are detected and shown to members. *Heuristic; see F-01.*
- **G4. Local web safety.** T3 cannot read data or perform actions (loopback bind, Host check,
  CSRF tokens, CSP, SameSite=Strict cookies).
- **G5. Least retention.** No plaintext on disk except by the user's choice (export). Keys stay
  in memory only while a session is unlocked.

## Explicit non-goals

- **Integrity or availability against T1.** T1 can delete or corrupt the file, **roll it back to an
  earlier copy (F-03)**, remove someone from an owner list, or forge "agreed so far" markers on
  proposals (F-01, residual). We aim to *detect* some of these, not to prevent them.
- **Security against coercion.** A member can be pressured into sharing, or into revealing their
  passphrase (DEF-016). Participants with current safety concerns are screened out of this study.
- **Metadata privacy** (ASM-020).
- **Forward secrecy on revocation.** Items can't be changed after creation, so a revoked grantee
  already saw the content (ASM-021).
