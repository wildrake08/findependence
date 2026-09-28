# VV-001: System verification and validation of Findependence at 9e84fa8

Prepared by ACT-002 on 27 September 2026. This is analysis and evidence at proposal level: it changes no code,
Requirement, Claim, or ratified artifact. ACT-002 also built most of what is evaluated here, so read it with that
bias in mind. A clause-level audit of every Requirement is in
[Appendix A](VV-001-appendix-requirement-audit.md). Raw results are in
[REPRO-RUN-018](../runs/REPRO-RUN-018.txt) and [VV-RUN-001](../runs/VV-RUN-001.txt).

**In one paragraph.** At 9e84fa8 the build reproduces cleanly: every suite passes twice, check and trace pass, and
54 of 54 end-to-end checks pass on the real server. It meets every measurable quality gate in ROADMAP-ALPHA §3:
axe-core, Tab walk, phone table semantics, no sideways scroll, server time, and phone height.

Of the 58 accepted product Requirements, 22 are Verified, 5 are Not Verified, and 31 are Indeterminate.
- **Not Verified, specification defects (3):** later accepted Requirements changed the behaviour of REQ-102,
  REQ-112, and REQ-117 without amending them.
- **Not Verified, implementation defects (2):** unlocked keys stay in memory past 15 minutes idle until the next
  request (REQ-123), and "sent twice changes once" holds only for the last 64 forms (REQ-165). Both were
  demonstrated by execution.
- **Indeterminate (31):** some clause has no test that asserts it. Security-critical encryption properties are
  among them.

Every validation claim is Indeterminate, because no representative user has used the product.

**The overall system V&V conclusion is negative for full conformity, and Indeterminate for fitness for use.** The
released v0.7.1-alpha's Claims CLM-033 and CLM-034 overstate what the evidence supports (F-00).

---

## 1. System baseline

| Item | Value |
|---|---|
| System | Findependence, a local-first household economic record: `core/` (domain rules, IE-101..110) and `app/` (encrypted vault, sessions, HTTP interface, IE-201..205) |
| Version | Git commit `9e84fa899d16e8a4524074b3bd876878f69e99af`, branch `findependence/ux-005` (pushed to origin): v0.7.1-alpha (`fa88014`, code identical to `a39d7b7`) plus WI-051 (`85a0725`: stylesheet and "about" wording only; `git diff a39d7b7 9e84fa8 -- core app/lib` touches only `web.ex` and `web/html.ex`) |
| Configuration | `mix findependence.serve <vault> <port>` with `ERL_CRASH_DUMP_SECONDS=0`; default vault parameters (PBKDF2 ≥ 600,000 iterations); 15-minute idle lock; MIX_ENV=dev (the only documented run mode) |
| Deployment architecture | One BEAM process serving HTTP on 127.0.0.1 to a browser on the same device; one encrypted vault file per household; no network egress by design (REQ-124) |
| Execution environment (evaluated) | Linux 6.12.54-linuxkit aarch64 dev container; Elixir 1.20.4 / OTP 29; Python 3.13.5; headless Chromium 154.0.8037.57 (system-ui resolves to DejaVu Sans) |
| External interfaces | Browser over loopback HTTP; the vault file; the export file (JSON, `export.json`) and the bring-in file; the terminal for `mix` tasks. No bank or network services |
| Intended users | ACT-001, ACT-002, and testers ACT-001 invites (REV-034 alpha stage) |
| Intended uses | Internal testing of the alpha capabilities with made-up data only: no real financial or personal information, and no passphrase used elsewhere (REV-034; manifest `releases.alpha`) |
| Requirements | 58 accepted (`specified`) product Requirements in `project/realization/requirements*.yaml` (REQ-101..166), plus REQ-163 (`proposed`). REQ-001..016 govern the assurance tooling and are outside this system |
| Acceptance criteria | None recorded per Requirement (F-08). Clause-level criteria derived from each statement (Appendix A); ROADMAP-ALPHA §3 "seamless UX contract" quality gates |
| Authorities | CONSTITUTION.md, GOVERNANCE.md; PRI-001..003; CTX-001 (local-first, no advice; Sumner, WA); WCAG 2.x as used by the UX contract; REV-034 (alpha scope); GATE-016 (security, ethics, and professional review, pending) |
| Assurance level | Alpha prototype. Implementation-level Claims only (I-014). Explicitly **not** a security assurance (DEF-026, DEF-028; REV-034 defers GATE-016 until after the alpha) |

**Outside this baseline, and not concluded on:** the pilot stage (real households, real data), which requires
GATE-016 first; other operating systems, browsers, devices, and assistive technology; `MIX_ENV=prod` builds;
concurrent use by separate devices.

## 2. V&V basis

- **Verification basis:** the 58 accepted Requirements, each decomposed into observable clauses (Appendix A), plus
  the ROADMAP-ALPHA §3 quality gates. A Requirement is **Verified** only if every clause has a passing test that
  asserts it. **Not Verified** means evidence shows a violation. Anything else is **Indeterminate**.
- **Validation basis:** the alpha's intended use (REV-034) and the capabilities it exposes (CAP-001..013 in
  `project/semantic/`), read against the Outcomes they serve (OUT-001..009). Validation needs evidence from the
  intended users in the intended context. WALKTHROUGH-001 and STUDY-001 are the planned sources, and neither has
  run.
- **Governing rule (CONSTITUTION, gate rule):** passing a lower-level gate does not imply a higher one. Code
  conformance does not establish Capability or Outcome.

## 3. Traceability matrix

Upward traceability (Requirement → Mechanism → Capability → Purpose) is checked by `scripts/trace`, which passes at
9e84fa8. Per-clause evidence and gaps for each row are in Appendix A. Method codes: **T** test, **I** inspection,
**D** demonstration by execution, **A** analysis.

### 3a. Requirements (verification)

| ID | Requirement (short) | V or V | System scope | Method | Acceptance criterion | Evidence | Result | Residual risk |
|---|---|---|---|---|---|---|---|---|
| REQ-101 | Non-empty owner set | Verification | core | T | App. A clauses C1–C3 | household_test, randomized_test | Verified | "Economic item" undefined |
| REQ-102 | Read iff owner or grantee | Verification | core | T, I | "only if" holds for every member | shared_value_test:177/191; vault_test:98 show joiners read | **Not Verified** | Spec conflict with REQ-115/119/148 (F-01) |
| REQ-103 | Grants by owners, all consent, any revokes | Verification | core | T | C1–C4 | household_test:54–73; randomized_test | Verified | — |
| REQ-105 | Append-only ledger readable by owners | Verification | core | T | C1–C3 | household_test:121/135; randomized_test:295/324 | Verified | Deletion exception unstated |
| REQ-106 | Aggregates over visible items only | Verification | core | T | C1–C2 | randomized_test:314/506; module tests | Verified | Web views only spot-checked |
| REQ-107 | Owner-set change rules | Verification | core | T | C1–C5 | household_test; exit_test; randomized_test | Verified | Stale REQ-104 citations |
| REQ-108 | Sole-owner deletion removes everything | Verification | core | T | C1–C8 | exit_test:43–55 | Indeterminate | C5 (pending proposals removed) unasserted |
| REQ-110 | Unilateral departure | Verification | core | T | C1–C5 | exit_test:85–109; randomized_test | Verified | — |
| REQ-111 | Values are member items; none predefined | Verification | core | T | C1–C4 | alignment_test:18–28 | Verified | — |
| REQ-112 | Link any visible item to any visible value | Verification | core | T, I | C1 holds for every visible item | alignment_test:49; balances_test:113 show refusals | **Not Verified** | Spec conflict with REQ-134 (F-01) |
| REQ-114 | Lost visibility leaves distribution silently | Verification | core | T | C1–C7 | alignment_test:213–241 | Indeterminate | "Silently" untested; hidden links kept in own record |
| REQ-115 | Joining a value needs joiner and owners | Verification | core | T | C1–C6 | shared_value_test:172–203 | Verified | — |
| REQ-116 | Withdraw from a shared value | Verification | core | T | C1–C3 | shared_value_test:211–217 | Verified | Terms undefined |
| REQ-117 | Export own items and links, nothing else | Verification | core | T, I | "nothing else" | exit_test:79 asserts plans, goals, etc. | **Not Verified** | Spec conflict with REQ-155/164 (F-01) |
| REQ-118 | Keys encrypted under PBKDF2 ≥ 600k, 16-byte salt | Verification | app | T | C1–C6 | vault_test:41/55; crypto_test:45 | Indeterminate | No KAT, salt, or key-absence test; parameters read from file (F-05) |
| REQ-119 | Per-item key, sealed to readers | Verification | app | T | C1–C6 | vault_test:62/88/115; model_test | Indeterminate | Per-item key distinctness unasserted |
| REQ-120 | Ledger sealed to owners, re-sealed | Verification | app | T | C1–C6 | vault_test:77; model_test; tamper_test:54 | Indeterminate | Joiner re-seal unasserted; self-contradictory wording |
| REQ-121 | Links and deletions under member key | Verification | app | T | C1–C3 | vault_test:104 | Indeterminate | No file-level or cross-member test |
| REQ-122 | No plaintext content in file | Verification | app | T, D | C1–C5 | vault_test:115; readings_crypto_test:171; VV-RUN-001 P | Indeterminate | Deletion records and links untested |
| REQ-123 | Loopback, Host, CSRF, key discard | Verification | app | T, D, I | C1–C5 | web_test:46–82; VV-RUN-001 P, D1 | **Not Verified** | Keys held past 15 min idle (F-02); CSRF tested on 2 routes |
| REQ-124 | No outbound connections or remote loads | Verification | app | T, I, D | C1–C2 | web_test:97/105; VV-RUN-001 P | Indeterminate | Static grep, one page, one snapshot |
| REQ-125 | Proposer or owner withdraws | Verification | core | T, D | Per recorded interpretation | exit_test:131–158; VV-RUN-001 D2 | Verified | Interpretation's premise false (F-03) |
| REQ-128 | Distribution rules | Verification | core | T | C1–C8 | alignment_test:82–200 | Verified | Rounding unstated |
| REQ-129 | Frequencies | Verification | app | T | C1–C6 | frequency_test; alignment_test | Indeterminate | "Wherever shown" partial |
| REQ-130 | Accounts and debts as items | Verification | core | T | C1–C5 | balances_test:18/29 | Indeterminate | "Fixed" unasserted; stale type list |
| REQ-131 | Readings by owners, append-only | Verification | core, app | T | C1–C7 | balances_test:38–57; balances_web_test | Verified | — |
| REQ-132 | Latest for readers, all for owners | Verification | core, app | T | C1–C3 | balances_test:84; readings_crypto_test:70 | Verified | — |
| REQ-133 | Per-reading keys | Verification | app | T | C1–C7 | readings_crypto_test:70–147 | Indeterminate | New-owner and relinquish cases untested |
| REQ-134 | Balances not in distribution, not linkable | Verification | core | T | C1–C2 | balances_test:113 | Indeterminate | Debt link untested |
| REQ-135 | Account and debt pages; home list | Verification | app | T | C1–C7 | balances_web_test; ux005_test | Indeterminate | Home link untested; "no forms on home" literally false |
| REQ-136 | Optional date | Verification | app | T | C1–C6 | cash_flow_web_test:60; schedule_test | Verified | — |
| REQ-137 | Schedule arithmetic | Verification | core | T | C1–C4 | schedule_test:13–43 | Verified | — |
| REQ-139 | Next sixty days | Verification | app | T | C1–C5 | cash_flow_web_test:126–151 | Indeterminate | Horizon untested; cites superseded REQ-138 |
| REQ-140 | Set-aside for lumpy bills | Verification | core, app | T | C1–C4 | schedule_test:126; cash_flow_web_test | Indeterminate | Yearly and 2/3-month cases untested |
| REQ-142 | Private plans | Verification | core, app | T | C1–C9 | plans_projection_test; v03_web_test | Verified | Vacuous assertion (F-06) |
| REQ-143 | Plan side by side; labelled everywhere | Verification | app | T | C1–C3 | v03_web_test:151–164 | Indeterminate | "Every place" not enumerated |
| REQ-144 | Job-dependency marks | Verification | core, app | T | C1–C4 | plans_projection_test:99/177; v03_web_test | Verified | — |
| REQ-145 | Debt what-ifs as facts | Verification | core, app | T | C1–C6 | v03_web_test:251–271; ux005_test | Indeterminate | Grantee view and "no payment order" untested |
| REQ-146 | Emergency-fund goal | Verification | core, app | T | C1–C5 | v03_web_test:280; plans_projection_test:214 | Indeterminate | Privacy and no-default untested |
| REQ-147 | Set-aside rate | Verification | core, app | T | C1–C3 | v03_web_test:304; plans_projection_test:235 | Verified | — |
| REQ-148 | Shared plans | Verification | core, app | T | C1–C6 | v03_web_test:337–375 | Indeterminate | "Steps never change" untested |
| REQ-149 | Retirement accounts | Verification | core, app | T | C1–C5 | retirement_test:48–59; v04_web_test | Indeterminate | Reading rules for these types untested |
| REQ-150 | Retirement assumptions | Verification | core, app | T | C1–C9 | retirement_test:67–133; v04_web_test | Indeterminate | Some clears untested; 0 handled differently |
| REQ-151 | Year-by-year projection | Verification | core, app | T | C1–C6 | retirement_test:138–175; v04_web_test | Verified | — |
| REQ-152 | How long it lasts | Verification | core, app | T | C1–C7 | retirement_test:208–235 | Indeterminate | "At 100" render untested; conflicts with REQ-153 (F-01) |
| REQ-153 | Sensitivity ±2 | Verification | core, app | T | C1–C5 | retirement_test:239; v04_web_test:200/245 | Indeterminate | "How long" for alternatives untested |
| REQ-154 | No suggestions on retirement | Verification | app | T | C1–C4 | v04_web_test:265; glossary_test | Indeterminate | Phrase-list heuristic only |
| REQ-155 | Export carries plans etc. | Verification | core | T | C1–C7 | import_test:186/224 | Indeterminate | Reference filtering untested |
| REQ-156 | Bring-in remaps | Verification | core, app | T | C1–C12 | import_test:237/314; v05_web_test:158 | Indeterminate | Remapped endpoints, history absence untested |
| REQ-157 | Untrusted file checks | Verification | core, app | T | C1–C8 | v05_web_test:233/264/318; import_test:394 | Verified | — |
| REQ-158 | Preview, confirm, cancel | Verification | app | T | C1–C5 | v05_web_test:158/213; e2e W10 | Indeterminate | Goals count, navigation away untested |
| REQ-159 | Same file twice refused | Verification | core, app | T | C1–C4 | import_test:362; e2e W10 | Verified | Byte-identical files only |
| REQ-160 | Which account an item goes through | Verification | core, app | T | C1–C8 | attach_test:52–151; cp014_web_test | Indeterminate | Change, "other" type untested |
| REQ-161 | Home's next 14 days | Verification | app | T | C1–C10 | cash_flow_web_test:81; attach_test | Indeterminate | Four-day cap, "more" line, link untested |
| REQ-162 | Next 12 months | Verification | core, app | T | C1–C9 | plans_projection_test:49/60 | Indeterminate | Debt payoff never exercised |
| REQ-163 | Dated amount changes | Verification | — | I | — | state `proposed` | Not Applicable | Not accepted; deferred to DEF-026 |
| REQ-164 | Attachments in export | Verification | core, app | T | C1–C5 | import_test:331/342; cp014_web_test:167 | Verified | — |
| REQ-165 | Sent twice changes once | Verification | app | T, D | C1–C6 | ux004_test:89/152; e2e W11; VV-RUN-001 D3 | **Not Verified** | Re-applies after 64 forms; no-token bypass (F-04) |
| REQ-166 | Confirm before delete | Verification | app | T | C1–C6 | web_ux_test:146; ux004_test:216; e2e | Indeterminate | Value delete untested; handler doesn't enforce |

### 3b. Quality gates and system characteristics (verification)

| ID | Need / criterion source | V or V | Scope | Method | Acceptance criterion | Evidence | Result | Residual risk |
|---|---|---|---|---|---|---|---|---|
| QG-1 | ROADMAP §3 accessibility | Verification | app pages | T | axe-core 0 violations, 0 needs-review at 1200 and 390 px on every page | VV-RUN-001 A (70 states, 140 results) | Verified | 70 captured states, not every data state; Chromium only |
| QG-2 | ROADMAP §3 table semantics | Verification | app pages | T | Tables keep table/row/header/rowgroup roles on phones | VV-RUN-001 A (21 of 21 table pages equal) | Verified | Chromium tree only; no screen reader |
| QG-3 | ROADMAP §3 Tab walk | Verification | app pages | T | Every control reached in DOM order, visible focus ≥ 3:1 | VV-RUN-001 A (13.39:1 minimum) | Verified | Radios reached by arrows (native) |
| QG-4 | ROADMAP §3 phone layout | Verification | app pages | T | No overflow or clipping at 390 px | geometry.py 0 failures at 390 and 320 px | Verified | "Nothing clipped" measured as no sideways scroll |
| QG-5 | ROADMAP §3 screenshots reviewed, gallery updated | Verification | app pages | review | A person reviews screenshots against UX-001's target | none for this build | Indeterminate | Needs a human |
| QG-6 | ROADMAP §3 performance | Verification | app | T | Every page < 50 ms server time at 200 items | scale.exs: max 21.7 ms over 9 page types | Verified | Dev container, not a household laptop; handler time, not network |
| QG-7 | ROADMAP §3 home size | Verification | app | T | Home at 50 items on a phone ≤ 7,812 px | 7,218 px | Verified | DejaVu metrics |
| QG-8 | ROADMAP §3 earlier pages unchanged | Verification | app | T | Changes limited to those declared | UI-RUN-008 height comparison (working tree, same code) | Verified | Heights only, not pixels |
| QG-9 | ROADMAP §3 words: glossary, no judgment words | Verification | app | T | glossary_test passes over its page set | REPRO-RUN-018 B | Verified | Word lists, not meaning |
| QG-10 | ROADMAP §3 no JavaScript | Verification | app | T, D | CSP forbids scripts; forms work without JS | web_test:97; VV-RUN-001 P header; e2e uses plain HTTP | Verified | — |
| SC-1 | Reproducibility | Verification | whole | D | Clean checkout builds; all suites pass twice; check and trace pass | REPRO-RUN-018 | Verified | One environment |
| SC-2 | End-to-end workflows over HTTP | Verification | whole | D | e2e driver 54/54 on a real server | REPRO-RUN-018 G | Verified | Scripted client, not a browser |
| SC-3 | Hostile input at the HTTP boundary | Verification | app | D | Foreign Host 421; traversal 404; 20 MB 413; bad encoding and no CSRF 403; server survives | VV-RUN-001 P | Verified | Probes, not a fuzzing campaign |
| SC-4 | Restart continuity | Verification | app | D | After kill -9 when idle, data intact and unlockable | VV-RUN-001 R | Verified | Idle kill only |
| SC-5 | Crash during a write | Verification | app | I | Vault never left partial | vault.ex temp file + rename | Indeterminate | No fsync; power-loss durability unknown (F-11) |
| SC-6 | Security of the vault design | Verification | app | — | GATE-016 1_security_review | none (pending) | Indeterminate | DEF-026, DEF-028 open |
| SC-7 | Concurrency (two writers) | Verification | app | T | Simultaneous writes refused; stale copy reloads | store_concurrency_test (REPRO-RUN-018 B) | Verified | Same device only |
| SC-8 | Logging without contents | Verification | app | T, D | Refusals logged without typed values | refusal_log_test; VV-RUN-001 P (0 typed values in 31 lines) | Verified | — |
| SC-9 | Cross-browser and assistive tech | Verification | app | — | Works in Safari, Firefox, screen readers, High Contrast | none | Indeterminate | Chromium emulation only |

### 3c. Intended uses (validation)

| ID | Need | V or V | Scope | Method | Success / unacceptable outcome | Evidence | Result | Residual risk |
|---|---|---|---|---|---|---|---|---|
| VAL-1 | Safe internal testing: testers use only made-up data (REV-034) | Validation | whole | inspection of notices | Every entry point says "made-up data only"; nobody enters real data | release_notice_test; notices on unlock and setup (VV-RUN-001 P) | Indeterminate | Whether testers comply is unobserved |
| VAL-2 | Understand one's money in and out and what it serves (CAP-001, CAP-005; OUT-001, OUT-002) | Validation | whole | none with users | A tester records their items and values and says correctly what the totals mean | ACT-001 usage reports (n=1, UX-001), not structured | Indeterminate | No representative user |
| VAL-3 | See shortfalls coming (CAP-010, CAP-011; OUT-001, OUT-006) | Validation | whole | e2e demonstration only | A tester finds the next below-zero day and what causes it | e2e W5/W6 (scripted) | Indeterminate | Scripted client is not a user |
| VAL-4 | Explore "what if" without changing reality (CAP-007; OUT-006, OUT-007) | Validation | whole | e2e demonstration only | A tester builds a plan and reads its effect correctly | e2e W7 | Indeterminate | As above |
| VAL-5 | Retirement under one's own assumptions, no advice (CAP-012; PRI-001) | Validation | whole | e2e demonstration only | A tester reaches a result and doesn't read it as a recommendation | e2e W9; v04 tests; UX-004 review | Indeterminate | "Not advice" is a perception claim |
| VAL-6 | Share with consent; keep one's own standing (CAP-001, CAP-006; OUT-004, OUT-005; PRI-002) | Validation | whole | e2e demonstration only | Two testers share and agree without surprises about who sees what | e2e W3/W4 | Indeterminate | No multi-person session observed |
| VAL-7 | Leave with one's record (CAP-002, CAP-009; OUT-005, OUT-008) | Validation | whole | e2e demonstration only | A tester leaves and brings their record into a new household | e2e W10 | Indeterminate | As above |
| VAL-8 | Bounded burden (OUT-009) | Validation | whole | none | A monthly five-minute check suffices | none | Indeterminate | Needs STUDY-001 |
| VAL-9 | Usable with a keyboard, screen reader, phone (UX contract) | Validation | app | automated proxies | People using them complete T1–T7 | QG-1..4 only | Indeterminate | WALKTHROUGH-001 not run |
| VAL-10 | Pilot use with real households | Validation | — | — | — | — | Not Applicable | Outside this baseline's intended use; requires GATE-016 |

## 4. Coverage analysis

**Coverage universe:** 59 product Requirements (58 accepted + 1 proposed); 10 ROADMAP §3 gates; 9 system
characteristic claims; 10 intended-use claims. Every member is dispositioned above.

| Dimension | Evaluated | Partial | Not evaluated |
|---|---|---|---|
| Requirements (58 accepted) | 22 Verified, 5 Not Verified | 31 Indeterminate (clause gaps listed in App. A) | 0 |
| Intended uses (9 in scope) | — | 5 demonstrated by scripted workflow | 9 without user evidence |
| Components | core (122 tests), app (224), tooling (69) | — | Browser rendering outside Chromium |
| Interfaces | HTTP (e2e, probes), vault file, export and bring-in files | Terminal setup (piped input only) | Printing |
| States | Locked, unlocked, idle-expired, stale form, refused, repeated, not-found | In-flight double click (`:busy`) | Kill during a write |
| Environments | One Linux dev container, headless Chromium | — | macOS, Windows, iOS, Android, Safari, Firefox |
| Data classes | Made-up demo family; seeded 10/50/200 items; malformed files (35 cases) | — | Real data (out of scope) |
| Actor classes | Owner, joint owner, grantee, prospective joiner, non-member, departed member | Proposer removed by an owner change (demonstrated, F-03) | Tampering member at the file level, beyond tamper_test |
| Failure modes | Wrong passphrase, tampered file, stale form, oversized body, foreign Host | Idle keys (F-02), token eviction (F-04) | Power loss, disk full |
| Quality characteristics | See §4a | | |

### 4a. Characteristic classification

| Characteristic | Classification | Where evaluated |
|---|---|---|
| Functional behaviour, workflows | Applicable | §3a; SC-2 |
| Interfaces and interoperability | Applicable | SC-2, SC-3; REQ-157, REQ-164 |
| Data integrity and correctness | Applicable | randomized_test invariants; REQ-105, REQ-131 |
| State transitions and lifecycle | Applicable | REQ-107..110, REQ-123, REQ-165 |
| Boundary and limit behaviour | Applicable | REQ-157 (1 MB), SC-3, QG-6 |
| Invalid, malformed, adversarial input | Applicable | SC-3; import_test:394; tamper_test |
| Error handling and failure | Applicable | SC-3, SC-4; DEF-035 tests |
| Security | Applicable, **Indeterminate** | SC-6 (GATE-016 pending); F-02, F-05 |
| Privacy | Applicable | REQ-102..122 visibility; F-01 |
| Safety | Not applicable: no physical harm pathway. Financial harm is covered under "no advice" (VAL-5) and the alpha's made-up-data rule (VAL-1) | — |
| Performance, capacity, latency | Applicable | QG-6, QG-7 |
| Reliability, availability | Applicable, partly Undetermined | SC-4; no soak test (single-user local app) |
| Resilience, recovery | Applicable, partly Undetermined | SC-4, SC-5 (F-11) |
| Concurrency | Applicable | SC-7; REQ-165 `:busy` untested |
| Scalability | Applicable within one household | QG-6 (200 items); beyond that, not intended |
| Compatibility | Applicable, **Undetermined** | SC-9 |
| Usability | Applicable, **Undetermined** | VAL-2..9 (no users) |
| Accessibility | Applicable | QG-1..4 (automated); VAL-9 (human) Undetermined |
| Deployability, configuration | Applicable | SC-1; README steps reproduced |
| Upgrade, migration, rollback | Applicable | REQ-164 (v1/v2 files still read); vault format upgrades not evaluated (Undetermined) |
| Restoration | Applicable | README says copies are not safe backups (F-03 of the self-review); export is the supported path (REQ-117/155) |
| Observability, diagnosability | Applicable | SC-8 |
| Operability | Applicable | README run steps reproduced; the `serve` task |
| Maintainability | Applicable where visible | format check; check and trace; test defect F-06 |
| Compliance with authorities | Applicable, **Undetermined** | GATE-016 2_ethics and 3_professional checks pending; CTX-001 notes |

## 5. Findings

| ID | Kind | Finding | Affected claims | Disposition proposed |
|---|---|---|---|---|
| **F-00** | Evidence overstatement | CLM-033 and CLM-034 (the released v0.7.1-alpha) say the code "satisfies" REQ-102, REQ-112, REQ-117, REQ-123, and REQ-165, and many Requirements found Indeterminate here, "as specified and tested". Clause-level evidence shows 5 are violated as written and 31 are only partly evidenced. The same code is in v0.7.1-alpha (`git diff` touches only the stylesheet and wording) | CLM-033, CLM-034; by the same reasoning CLM-031, CLM-032 | Defeater against CLM-033 and CLM-034. Narrow them to the Verified set, or restate them as "passes its tests" |
| **F-01** | Specification defect | Later accepted Requirements changed behaviour without amending earlier ones: REQ-102 (joiners read), REQ-112 (only activity items link), REQ-117 (export carries more). Also REQ-152 versus REQ-153 (±2 comparisons), REQ-135 ("no forms on home" is literally false), REQ-139 (cites superseded REQ-138), REQ-130 (types omit 401(k) and IRA), REQ-120 (self-contradictory) | REQ-102, 112, 117, 120, 130, 135, 139, 152 | One ChangeProposal to amend or supersede the wording. No code change |
| **F-02** | Implementation defect (or wording) | Unlocked keys are discarded on the first request after 15 minutes idle, not at 15 minutes. Demonstrated: a session idle 16 minutes is still in memory (VV-RUN-001 D1) | REQ-123; CLM-034 | Defeater. Either a sweep that discards expired sessions (for example a timer in `Sessions`), or amend REQ-123 to the lazy rule. Security-relevant, so include in GATE-016 |
| **F-03** | Specification defect | REQ-125's recorded interpretation assumes a proposer who stops owning has lost their proposals. That is true for relinquishing, false for an agreed owner change: the proposal stays pending, the ex-owner can't withdraw it, and the remaining owner can still approve it (VV-RUN-001 D2) | REQ-125, REQ-107 | Defeater. Drop a member's proposals whenever they stop owning the item (as relinquish does), or let the proposer withdraw |
| **F-04** | Implementation defect | "At most once" is bounded: only the last 64 claimed form tokens are remembered, so a form resent after 64 later forms applies again. A request without `_form` is never deduplicated (browsers always send it) (VV-RUN-001 D3) | REQ-165; CLM-034 | Defeater. Refuse `/act/*` posts without a `_form` token, and keep claimed tokens for the whole session |
| **F-05** | Evidence deficiency | 31 Requirements have untested clauses. Most material: the crypto properties (REQ-118 PBKDF2 known-answer test, salt length, key absence from the file; REQ-119/133 per-item and per-reading key distinctness; REQ-121/122 deletion records), and REQ-118's parameters read from the vault file at unlock | 31 Requirements (App. A) | Add clause tests (list in App. A). Hand REQ-118's parameter observation to GATE-016 |
| **F-06** | Test defect | `core/test/plans_projection_test.exs:137-144` asserts on a value it has just replaced, so it can't fail | REQ-142 (evidence quality only) | Fix the assertion |
| **F-07** | Observation | Delete confirmation (REQ-166) is enforced by the pages, not the handler: a direct POST to `/act/delete` deletes. CSRF still applies | REQ-166 | Record as intended, or enforce in the handler |
| **F-08** | Specification deficiency | Requirements have no acceptance criteria, so every verdict depends on how a statement is split into clauses (done by ACT-002 and its subagents) | All | Add criteria when Requirements are next revised, starting with the security ones |
| **F-09** | Validation evidence gap | No representative user has used the product. WALKTHROUGH-001 and STUDY-001 have not run | VAL-1..9 | Run WALKTHROUGH-001 (REV-056 already orders it next) |
| **F-10** | Assurance gap | Security, ethics, and professional reviews (GATE-016) are pending | SC-6; pilot | As planned: required before any real data |
| **F-11** | Residual risk | The vault write is temp file + rename with no fsync. Survives a crashed process; power-loss durability is unknown | SC-5 | Decide whether to fsync the file and directory |
| **F-12** | Ambiguity | A previewed bring-in file stays pending across navigation until the session ends; REQ-158 says nothing is saved "if they leave the page" | REQ-158 | Clarify the wording, or drop the pending file on any other page |
| **F-13** | Minor inconsistency | A retirement contribution of "0" clears it on the web; the core function refuses 0 | REQ-150 | Align them |

**Prior evidence affected:** F-00 weakens CLM-031..034 and the corresponding ASMT records, which judged the
Requirements met from passing tests. Nothing here invalidates a test result, a reproduction, or a quality-gate
measurement.

## 6. Evidence register

| ID | Source | Time and version | Method or tool | Baseline | Integrity and provenance | Supports |
|---|---|---|---|---|---|---|
| REPRO-RUN-018 | `project/assurance/runs/REPRO-RUN-018.txt` | 2026-09-27T22:49Z | git worktree, `mix test` ×2, check, trace, e2e | 9e84fa8 (clean) | Commit hash recorded; worktree clean before and after | §3a (all T), SC-1, SC-2, SC-7, SC-8, QG-9 |
| E2E-JSON | `project/assurance/vv/e2e-results-9e84fa8.json` | same run | `alpha_e2e.py` | 9e84fa8 | Written by the driver; 54 records | SC-2, VAL-3..7 |
| VV-RUN-001 P | `runs/VV-RUN-001.txt`; `vv/probes.sh` | same day | curl, `/proc/net/tcp` | 9e84fa8 server | Script committed alongside | REQ-122..124, SC-3, SC-8 |
| VV-RUN-001 R | same | same | kill -9, restart, login | 9e84fa8 | Vault sha256 prefix compared | SC-4 |
| VV-RUN-001 D1–D3 | same; `vv/demo_req123.exs`, `demo_req125.exs`, `demo_req165_test.exs` | same | `mix run`, ExUnit | 9e84fa8 | Scripts committed; re-runnable | F-02, F-03, F-04 |
| VV-RUN-001 S | same; `analysis/scale/scale.exs` | same | handler timing, mean of 20 | 9e84fa8 | Existing script | QG-6, QG-7 |
| VV-RUN-001 A | same; `accessibility/*.py`, `axe.sh` | same | axe-core 4.10.2 (sha256 checked), geometry, tabwalk, axtree | 9e84fa8 captures | Pinned axe hash | QG-1..4 |
| UI-RUN-008 | `runs/UI-RUN-008.txt` | 2026-09-27 | forced-colours and height comparison | working tree = 85a0725 code | Code identical to 9e84fa8 | QG-8; WI-051 |
| APP-A | `analysis/VV-001-appendix-requirement-audit.md` | 2026-09-27 | clause audit by 4 AI subagents, read-only; 7 citations spot-checked; every Not Verified confirmed by ACT-002 | 9e84fa8 | Model-derived analysis: a reviewer should re-check any clause they rely on | §3a |

Screenshots, logs, measurements, and test assertions are kept distinct above. No human observation is used as
evidence in this record.

## 7. Residual risks and limitations

1. **One environment:** a Linux container with headless Chromium and DejaVu Sans. Results may differ on household
   devices, fonts, Safari, Firefox, or real phones.
2. **The Requirement audit is model analysis** (F-08, APP-A). A Verified result means "every clause as ACT-002 split
   it has an asserting test". A different split could find more gaps.
3. **Tests are the builder's own:** the same agent wrote the code, the tests, and this record. No independent
   verifier has reviewed any of it.
4. **Security is not assured** (F-10). Nothing here should be read as evidence that the vault resists an attacker.
5. **No user evidence** (F-09). Every fitness-for-use statement is open.
6. **Durability through power loss** (F-11), **vault format migration**, and **printing** were not evaluated.
7. **Probes are samples:** one network snapshot, a handful of hostile requests. This was not a fuzzing campaign or
   a full-session packet capture.
8. **Conclusions apply to 9e84fa8** and, for code-level findings, to v0.7.1-alpha (same code except the stylesheet
   and wording). They do not extend to later commits.

## 8. V&V conclusions

**Verification conclusion (scope: 9e84fa8, the evaluated environment, made-up data):**
- The build is reproducible, and it meets every measurable ROADMAP-ALPHA §3 gate (QG-1..4, QG-6..10).
- Of 58 accepted Requirements, 22 are **Verified**, 5 are **Not Verified**, and 31 are **Indeterminate**.
- The system therefore **does not conform** to its specified Requirements as written. Two violations are in the
  implementation (F-02, F-04); three are in the Requirements themselves (F-01).
- Security conformity is **Indeterminate** (GATE-016 pending).

**Validation conclusion (scope: the alpha's intended use, internal testing with made-up data):**
**Indeterminate** for every intended use. Scripted end-to-end runs show the workflows complete, but no intended user
has been observed, so fitness for use can't be established either way. Pilot use with real households is **Not
Applicable** to this baseline.

**Overall system V&V conclusion:** a positive conclusion is not permissible. Conditions 3 (acceptance criteria), 4
(sufficient evidence), 5 (no demonstrated violation), and 8 (a representative environment) of the system-level rule
are unmet. The smallest steps to a stronger conclusion:
1. amend the conflicting Requirements (F-01) and decide F-02 to F-04;
2. add the missing clause tests, crypto first (F-05);
3. run WALKTHROUGH-001 (F-09);
4. complete GATE-016 (F-10) before any real data.

## 9. Governance notes

- **Artifacts changed:** new files only: this record, Appendix A, REPRO-RUN-018, VV-RUN-001, and
  `project/assurance/vv/` (three demonstration scripts, a probe script, and the e2e results). No Requirement, Claim,
  Defeater, WorkItem, or manifest entry is changed.
- **Canonical inputs used:** CONSTITUTION.md, GOVERNANCE.md, project/manifest.yaml, SUBJ-001, TEL-001, PUR-001,
  PRI-001..003, CTX-001, the Requirement files, CAP and OUT artifacts, ROADMAP-ALPHA, REV-034, REV-056,
  claims.yaml (CLM-033, CLM-034), THREAT-MODEL.md, and the code at 9e84fa8.
- **Deterministic checks run:** REPRO-RUN-018 (all suites twice, format, check, trace, e2e) and VV-RUN-001.
- **Claims affected:** CLM-033 and CLM-034 (and by the same reasoning CLM-031, CLM-032) overstate. No Claim is
  changed here.
- **EvidenceCandidates:** REPRO-RUN-018 (clean reproduction of 9e84fa8, which WI-051 needs before release); VV-RUN-001
  D1–D3 (three demonstrated nonconformities); QG measurements.
- **Proposed, not filed:** Defeaters for F-00 (against CLM-033 and CLM-034), F-02 (REQ-123), F-03 (REQ-125), and
  F-04 (REQ-165); a ChangeProposal for F-01. These wait for ACT-001's decision.
- **Human gates requested:** whether to file the Defeaters and the ChangeProposal; whether to repair F-02 and F-04
  now or after WALKTHROUGH-001; whether to index VV-001 in the manifest.
