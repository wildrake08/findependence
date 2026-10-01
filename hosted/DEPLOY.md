# Deploying the hosted form

The hosted form is **not in service**. This guide is what a first deployment must satisfy (OPS-001, WI-084).
Under the chosen trust model (REV-111) the operator can read a member's information while they are signed in, as
sign-up tells them (REQ-180); these settings limit and record that access. The preflight check
(`FindependenceHosted.Preflight`) verifies every item marked **[checked]** and the server won't start if one fails.

## 1. Database (once, by the database's administrator)

```sh
psql -v owner_password='...' -v runtime_password='...' -v database=findependence -f rel/database-roles.sql
```

- `findependence_owner` runs migrations; `findependence_app` is what the server connects as. **[checked]: the
  runtime role can only read and write rows.**
- The server reaches the database over **TLS that verifies the server's certificate**, unless the database is on
  the same host (then `DATABASE_SSL=disable`). **[checked]**
- Encryption at rest for the database volume and its backups; backups encrypted with a key the database's
  administrators don't hold. Retention 35 days; a restore tested every quarter into an isolated environment.
  Deleted accounts remain in backups until retention ends.

## 2. Secrets (in a secret manager, or a root-owned file of mode 0600 read by systemd)

| Variable | Value | |
|---|---|---|
| `SECRET_KEY_BASE` | `mix phx.gen.secret` (64+ characters) | **[checked]**; rotating it signs everyone out |
| `ACCOUNT_HMAC_KEY` | `openssl rand -base64 32` | **[checked]**; **never rotate it**: accounts are found only by their number's keyed hash, and numbers aren't stored in clear |
| `PASSPHRASE_PEPPER` | `openssl rand -base64 32` | **[checked]**; **never rotate it**: every member's key is wrapped with it, so a copy of the database alone allows no passphrase guessing (REQ-197). If it's lost, members can still get in with their recovery keys |
| `HOUSEHOLD_STATE_KEY` | `openssl rand -base64 32` | **[checked]**; **never rotate it**: every household's records carry a code under it (REQ-198), and request identifiers derive from it (REQ-199). If it's lost, every household is refused until resealed (section 8) |
| `RELEASE_COOKIE` | `openssl rand -hex 32` | **[checked]**; required even with the console off |
| `DATABASE_URL` | `ecto://findependence_app:...@db.host/findependence` | the runtime role |
| `MIGRATION_DATABASE_URL` | `ecto://findependence_owner:...@db.host/findependence` | only for migrations |
| `DATABASE_RUNTIME_ROLE` | `findependence_app` | grants after each migration |
| `PHX_HOST` | the public host name | required |
| `TRUSTED_PROXIES` | the reverse proxy's address(es), e.g. `127.0.0.1` | so attempt limits count real clients |

The release's own `releases/COOKIE` file must be readable by its owner only (the build sets 0600). **[checked]**

Keep `PASSPHRASE_PEPPER` and `HOUSEHOLD_STATE_KEY` **apart from the database's backups**: whoever holds a backup and
these keys together is back to guessing passphrases offline and forging records unseen.

## 3. Host

- A dedicated user `findependence`; named operator accounts with multi-factor sign-in; no routine root logins;
  sessions recorded.
- The service unit `rel/findependence_hosted.service` (copy and set paths): its own user, `LimitCORE=0`
  **[checked]**, `NoNewPrivileges`, `ProtectSystem=strict`, and the rest of its hardening.
  `MemoryDenyWriteExecute` is deliberately not set: the Erlang runtime's just-in-time compiler needs it off.
- No swap, or swap only on encrypted (device-mapped) storage. **[checked]**
- `kernel.yama.ptrace_scope = 3` (no process may attach to another to read its memory, root included, until
  reboot). **[checked]**
- A firewall allowing outbound connections only to the database (REQ-124), and inbound only from the reverse
  proxy.
- A reverse proxy terminating TLS with HSTS and modern ciphers, forwarding to the app on loopback.

## 4. Starting, stopping, and checking

```sh
bin/findependence_hosted eval "FindependenceHosted.Release.migrate()"     # as the owner role
bin/findependence_hosted eval "FindependenceHosted.Preflight.report()"    # every check, non-zero exit on failure
systemctl start findependence_hosted                                      # runs the same checks at start
systemctl stop findependence_hosted                                       # SIGTERM; there's no remote stop
```

`/health/live` answers while the server runs; `/health/ready` answers 200 only while the database is reachable
(REQ-196): point the proxy's health check at it.

## 5. The remote console (break glass only)

The console is **off** (REQ-193): distribution doesn't run, so nothing can connect. To use it:

1. A written request naming the reason, approved by a second person; a time limit.
2. Restart the server with `OPERATOR_CONSOLE=on` and `OPERATOR_CONSOLE_APPROVAL=<the request's reference>`
   (letters, digits, `.`, `_`, `-`; without one the release won't start, REQ-193 AC-3). It records that the
   console was enabled, with the reference (audit, channel `release_boot`, `console_enabled:<reference>`), and each
   connection is recorded too (channel `remote_console`).
3. Connect with `OPERATOR_CONSOLE=on OPERATOR_CONSOLE_APPROVAL=<reference> bin/findependence_hosted remote`,
   recorded.
4. When done, restart without it, and note the request's outcome.

Crash dumps are always off (REQ-194); there is no setting to turn them on.

## 6. Audit and review

- Every audit record is also written to the server's log as one `audit id=… operation=… outcome=…` line
  (content-free), so shipping the journal off the host keeps a copy the database's administrators can't undo.
  Alert on each `operation=operator_access` line and on each `household records failed their check` line.
- Ship operator-access records off the host, to an append-only store with an alert on each:
  `bin/findependence_hosted eval 'FindependenceHosted.Release.operator_access_since("2026-10-01T00:00:00Z")'`
  (tab-separated: time, channel, resource, outcome; the listing itself is recorded).
- Each month, review those records, the host's access logs, and break-glass requests, and keep a short note.
- An independent audit of operator access before the first release and yearly.
- After any change here, check that REQ-180's disclosure still says truthfully what the operator can do.

## 7. Releases

Built only from a tagged commit on main and reproduced from a clean checkout (as REPRO-RUN-023), with
`mix findependence.verify_tools` passing; approved by someone other than the builder; security fixes within 72
hours for critical issues, monthly otherwise (ARCH-001 1.3).

## 8. A household refused because its records changed (REQ-198)

A page answering "Your household's records were changed outside this service" means the household's rows don't
match their code: someone wrote to the database other than through the service, or a restore left the code
behind. The log names the household. Nothing in it can be shown or changed until:

1. the change is investigated (who wrote, when, from the database's own logs), with a written request approved by
   a second person, as for the console;
2. the rows are restored from a backup taken before the change, **or**, if the review finds the rows as they are
   genuine, the household is resealed:

   ```sh
   bin/findependence_hosted eval 'FindependenceHosted.Release.reseal("<household id>", "<reference>")'
   ```

   which writes a fresh code over the rows as they are, and is audited with the reference.
