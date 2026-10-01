# OPS-001: operating controls for the hosted form under a trusted operator

**Status:** accepted (REV-112): WI-084 builds the parts that are code; the procedures are ACT-001's to own or
delegate. For the hosted form's first release; the hosted form is not in service.
**Why:** ACT-001 chose a trusted-operator model (REV-111, CP-024 option A). While a member is signed in, the server
holds their unwrapped key, so the operator could read their information (ASSESS-001 FND-22, accepted and disclosed
by REQ-180). What protects members is now how the service is run: these controls limit who can reach that memory,
make any access visible, and keep what is stored and logged minimal.

Each control says what it is, the threat it answers, how it is done (code, configuration, or procedure), and how it
is verified. "Done" marks what WI-073..WI-081 already built.

## A. Reaching members' information in memory

| # | Control | How | Verified by |
|---|---|---|---|
| A1 | **No remote console by default.** Distribution (the release's remote console, `remote` and `rpc`) is off in production; turning it on is a deliberate, recorded act | Code: rel/env.sh.eex sets `RELEASE_DISTRIBUTION=none` unless `OPERATOR_CONSOLE=on`; with it on, the node writes an operator-access audit record at boot naming that the console was enabled. Release commands (`eval`, migrations) still work | Test of the release script both ways; a release-boot test for the audit record |
| A2 | **Two people for any console or host access to production** (break glass) | Procedure: a written request naming the reason, approved by a second person, time-boxed; the console session recorded; access ends and the change is reverted | Access log and the audit records reviewed monthly (F3) |
| A3 | **No crash dumps or core dumps.** An Erlang crash dump or an OS core dump would write members' keys to disk | Code: rel/env.sh.eex exports `ERL_CRASH_DUMP_SECONDS=0` (today it doesn't: a gap). Host: `LimitCORE=0` in the service unit, `kernel.core_pattern` to a discard | Release-script test; the preflight check (E3) |
| A4 | **Memory not written to swap** | Host: no swap, or encrypted swap | Preflight check |
| A5 | **No debugging of the running process** | Host: `kernel.yama.ptrace_scope=3`; no debuggers installed; the service under its own user; no routine root logins (named accounts with MFA, sessions recorded) | Preflight check; access review |
| A6 | **Every operator connection and release command audited** | Done (WI-077): a node connecting writes an audit record; migrations and rollbacks are audited; audit records are append-only (WI-079 trigger) | foundation and operator-access tests |
| A7 | **Audit records leave the host and raise an alert** | Code: a release command lists operator-access records since a time; Ops: shipped to an append-only store outside the database's operator, with an alert on any operator_access record | A test of the command; an alert drill |

## B. Stored data and backups

| # | Control | How | Verified by |
|---|---|---|---|
| B1 | Database role separation, TLS with verification, append-only audit | Done (WI-079, WI-081) | wi081_roles_test, wi079_config_test |
| B2 | **Encryption at rest** for the database volume and backups | Provider configuration; backups encrypted with a key held apart from the database's administrators | Deployment checklist |
| B3 | **Backup retention and restore** | Procedure: retention stated (proposed 35 days); a restore tested each quarter into an isolated environment; deleted accounts and households persist in backups until retention ends, and REQ-180's disclosure says so | Restore drill record |
| B4 | **Secrets in a secret manager**, never in files on the host | SECRET_KEY_BASE, ACCOUNT_HMAC_KEY, PASSPHRASE_PEPPER and HOUSEHOLD_STATE_KEY (WI-085, REV-113), RELEASE_COOKIE, database passwords; readable only by the service; the pepper and the state key kept apart from the database's backups | Preflight check (variables present, cookie file mode) |
| B5 | **Rotation rules** | SECRET_KEY_BASE and RELEASE_COOKIE may rotate (members are signed out); database passwords rotate yearly; **ACCOUNT_HMAC_KEY must never rotate** (accounts are found only by their number's keyed hash, and the number isn't stored in clear), so it is generated once and protected ; nor must PASSPHRASE_PEPPER or HOUSEHOLD_STATE_KEY (WI-085, REV-113: every wrapped key and every household's code depend on them) | Procedure; documented in the deployment guide |

## C. Network and service

| # | Control | How | Verified by |
|---|---|---|---|
| C1 | TLS terminated at a reverse proxy, HSTS, modern ciphers only; the app listening on loopback; TRUSTED_PROXIES set to the proxy | Configuration; app side done (WI-079) | External TLS scan; wi079_config_test |
| C2 | **Outbound connections only to the database** (REQ-124), enforced by the host firewall as well as by the app | Firewall rule | Egress test (done) plus a firewall check |
| C3 | **Readiness checks the database** | Code: /health/ready runs a trivial query (today it doesn't) | A test with the database up and down |

## D. Building and releasing

| # | Control | How | Verified by |
|---|---|---|---|
| D1 | Releases built only from a tagged commit on main, reproduced from a clean checkout (as REPRO-RUN-022, -023) | Procedure (existing) | REPRO record per release |
| D2 | Tool and image pins | Done (WI-081) | verify_tools task |
| D3 | **Two-person release approval** | Procedure: the approver isn't the builder | Release record |
| D4 | **Patching:** security fixes within 72 hours for critical issues, monthly otherwise (ARCH-001 1.3) | Procedure; `mix hex.audit` in the gate | Gate output; patch log |

## E. Checking the host matches this plan

| # | Control | How | Verified by |
|---|---|---|---|
| E1 | A deployment guide listing every variable, role, and host setting above | Document | Review |
| E2 | A systemd unit template with hardening (own user, `NoNewPrivileges`, `ProtectSystem=strict`, `PrivateTmp`, `LimitCORE=0`) | Code: rel/findependence_hosted.service | Review; preflight |
| E3 | **A preflight check** run before start and on demand: required variables present and strong, cookie file mode, distribution off unless enabled, crash dumps off, core limit 0, swap off or encrypted, ptrace scope, database role (DbRoles.check!), database TLS | Code: a release command printing each check and failing on any | Tests of each check with good and bad settings |

## F. People and oversight

| # | Control | How |
|---|---|---|
| F1 | **Incident response:** who is called, how access is cut, how members are told | Runbook; notification duties depend on GATE-016's professional check (US and Washington rules) |
| F2 | **Least privilege for staff:** nobody has standing production access; access is granted per incident (A2) | Procedure |
| F3 | **Monthly access review** of audit records, host access logs, and break-glass requests | Procedure, with a short record each month |
| F4 | **Independent audit** of operator access and these controls before first release and yearly | Arranged by ACT-001 |
| F5 | **Disclosure kept true:** REQ-180's text checked against what operators can actually do, after each change here | Review step in each release |

## What WI-084 would build (code and configuration)

A1 (distribution off by default, audited when on), A3 (crash dumps off), A7 (the audit listing command), C3 (readiness
checks the database), E2 (service unit template), E3 (preflight check), and E1 (the deployment guide), each with
tests that fail without it. Everything else is a procedure for ACT-001 to own or delegate, and B2, B3, C1's proxy,
C2's firewall, and A4..A5 are settings of the deployment that E3 checks.

## Proposed Requirements (to be accepted with WI-084)

- **REQ-193:** In production, the hosted form shall run with no remote console unless one is deliberately enabled,
  and enabling it shall be recorded in the audit.
- **REQ-194:** The hosted form shall never write a crash dump or core dump, and shall refuse to start where it can
  detect that the host would write one, or would swap its memory unencrypted.
- **REQ-195:** The hosted form shall offer a check that reports, before it starts, whether its secrets, roles,
  connections, and host settings match the deployment guide, and shall not start if a required check fails.
- **REQ-196:** The hosted form's readiness shall depend on its database being reachable.

Derived from PRI-003 (a member's delegation to the operator is accountable) and REQ-180 (what the operator can do
is disclosed), as REQ-191 is (CP-022).
