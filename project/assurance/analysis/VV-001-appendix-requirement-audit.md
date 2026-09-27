# VV-001 Appendix A: requirement-by-requirement audit

Baseline: `findependence/ux-005` at `9e84fa8`. Companion to [VV-001](VV-001-system-verification-validation.md).

**How this was produced.** Requirements carry only a `statement`, with no separate acceptance criterion. So each
statement was split into atomic, observable clauses (C1, C2, …), and the criterion is "every clause holds". Four
AI subagents, delegated by ACT-002, read the statements, the code, and the tests (read-only). For each clause they
cited the test that asserts it (path:line), or recorded NONE or PARTIAL. ACT-002 then:

- spot-checked 7 cited tests: each exists at the cited line with the cited name;
- confirmed every **Not Verified** by execution or by reading the Requirement record (VV-RUN-001 D1–D3);
- corrected three results: REQ-123 (Indeterminate → Not Verified, demonstrated by D1), REQ-125 (Not Verified →
  Verified against its recorded `interpretation`, with a specification finding from D2), and REQ-163 (Not Verified
  → Not Applicable: state `proposed`, not an accepted Requirement).

Tests are counted as passing because REPRO-RUN-018 ran every suite twice, all passing. **Result rules:**
Verified = every clause has a passing test that asserts it. Not Verified = evidence shows the statement is violated.
Indeterminate = some clause lacks an asserting test, or needs a person or another environment.

Test paths are relative to the repository root. Line numbers are at 9e84fa8.

---

## Ownership, access, and exit (REQ-101 to REQ-118)

**REQ-101 · Verified.** Every item has a non-empty owner set of members; an owner-less set is rejected.
C1 non-empty at creation → core/test/household_test.exs:22; randomized_test.exs:299 (every step). C2 owners are
members → household_test.exs:30. C3 empty set rejected → household_test.exs:26.
Spec note: "economic item" is undefined (values, accounts, debts, and plans are items too).

**REQ-102 · Not Verified (specification conflict).** "Read an item if and only if owner or active grantee."
C1 owner reads → household_test.exs:37. C2 grantee reads → household_test.exs:45. C3 "only if" → **contradicted by
design.** A prospective joiner of a value or shared plan reads it before being an owner or grantee (household.ex
pending view; asserted in core/test/shared_value_test.exs:177, :191, and app/test/vault_test.exs:98). REQ-115,
REQ-119, and REQ-148 require this, and REQ-102 was never amended. → Finding F-01.

**REQ-103 · Verified.** Only owners create or revoke grants; a joint item's grant needs every owner; any one owner
may revoke. household_test.exs:54, :64, :73; randomized_test.exs:355, :360.
Gap (minor): an unrelated non-owner's revoke is covered only by the randomized test.

**REQ-105 · Verified.** Every ownership change, grant, and revocation is recorded append-only and readable by every
current owner. household_test.exs:121, :135; exit_test.exs:13, :93; randomized_test.exs:295 (replay), :324 (prefix),
:308; app/test/vault_test.exs:77.
Spec note: "append-only" versus REQ-108's deletion of the ledger is not stated as an exception.

**REQ-106 · Verified.** Aggregates count only what the requester can see. household_test.exs:145;
randomized_test.exs:314-320, :506; alignment_test.exs:200; plans_projection_test.exs:67; retirement_test.exs:175;
schedule_test.exs:102; app/test/model_test.exs:24.
Gap: "any household-level view" is open-ended; web pages are covered only by specific refutes.

**REQ-107 · Verified.** Owner-set changes need all current owners; an owner may remove only themselves, and one must
remain; nobody adds themselves. household_test.exs:84, :88, :97; exit_test.exs:13, :21, :27;
randomized_test.exs:342, :377. Note: the test descriptions still cite the superseded REQ-104.

**REQ-108 · Indeterminate.** A sole owner deletes alone; a joint owner cannot; the item, grants, pending proposals,
and ledger are removed; the deleter keeps an id+seq record. exit_test.exs:43-55; randomized_test.exs:289, :392;
vault_test.exs:110. **Gap:** C5 (pending proposals removed) has no assertion. The realistic case, a sole-owned value
with a pending joiner invite, is untested.

**REQ-110 · Verified.** A member owning nothing can leave alone; membership, held grants, and proposals naming them
are removed; owners are refused. exit_test.exs:85-109; randomized_test.exs:418-428; vault_test.exs (~:164).

**REQ-111 · Verified.** A value is a member-owned item of kind value under the item rules; no predefined values.
alignment_test.exs:18, :21, :27, :28; shared_value_test.exs:211; randomized_test.exs:164.

**REQ-112 · Not Verified (specification conflict).** "Link any visible item to any visible value." C1 is
**contradicted:** a value, an account or debt, or a plan as the item end is refused (alignment.ex:194, :197, :200;
asserted at alignment_test.exs:49-53 and core/test/balances_test.exs:113). REQ-134 narrowed this, and REQ-112 was
never amended. C2 unlink → alignment_test.exs:63. C3/C4 private links → alignment_test.exs:56, :39, :65, :274;
randomized_test.exs:453. → Finding F-01.

**REQ-114 · Indeterminate.** Losing visibility silently removes an item from the distribution, and link records
reveal nothing. alignment_test.exs:213, :220, :228, :234, :241; randomized_test.exs:453, :506.
**Gaps:** "silently" (no notice) is untested and untestable as worded. By design, a hidden link stays in the member's
own encrypted record (alignment.ex:14-16). Whether that "reveals anything" needs a ruling.

**REQ-115 · Verified.** Joining a value needs the joiner's and every owner's consent; the joiner sees it only after
every owner consents. shared_value_test.exs:172-203; randomized_test.exs:342, :349; vault_test.exs:94-98.

**REQ-116 · Verified.** A participant withdraws alone while another remains; the last may delete.
shared_value_test.exs:211-217; randomized_test.exs:377. Spec note: "participant" and "withdraw" are undefined.

**REQ-117 · Not Verified (specification conflict).** "Export … and nothing else." The export also carries readings,
plans, marks, goals, retirement assumptions, and attachments (exit.ex:52-105; asserted at exit_test.exs:79-80),
which REQ-155 and REQ-164 require. REQ-117 was never amended. C1–C3 → exit_test.exs:67-75; alignment_test.exs:260;
randomized_test.exs:401-413. → Finding F-01.

**REQ-118 · Indeterminate.** Private keys stored only encrypted under PBKDF2-HMAC-SHA256 (≥ 600k iterations, random
16-byte salt); a wrong passphrase fails and reveals nothing. C3 iterations → vault_test.exs:55; crypto_test.exs:45.
C5 wrong passphrase → vault_test.exs:41; web_test.exs:72. **Gaps:** no known-answer test for PBKDF2-HMAC-SHA256
(C2); the 16-byte salt is untested (C4); no test that private-key bytes are absent from the file (C1); "reveals
nothing" is only the same error atom. Observation for GATE-016: the iteration count and the `unsafe_test` flag are
read from the (plaintext) vault file at unlock (session.ex:38; vault.ex:48-49).

## Encryption and the interface boundary (REQ-119 to REQ-134)

**REQ-119 · Indeterminate.** Item content is encrypted under a per-item key and sealed only to readers.
vault_test.exs:62, :88, :115; web_test.exs:117; model_test.exs:24; tamper_test.exs:35. **Gap:** the per-item key
(distinct keys per item) is never asserted.

**REQ-120 · Indeterminate.** Ledger entries are sealed to owners at append and re-sealed to new owners and approved
joiners. vault_test.exs:77, :115; model_test.exs:24; tamper_test.exs:54. **Gap:** re-sealing to a prospective joiner
before their consent is allowed but never positively asserted. Spec defect: the statement gives a joiner (a
non-owner) ledger access, then says non-owners cannot read the ledger.

**REQ-121 · Indeterminate.** Links and deletion records are encrypted under a key only that member can unlock.
vault_test.exs:104 (keyed to "ana"); model_test.exs:24. **Gaps:** no file-level check of deletion records; no
cross-member decryption attempt.

**REQ-122 · Indeterminate.** No attribute, value label, link, ledger detail, or deletion record appears in plaintext.
vault_test.exs:115; readings_crypto_test.exs:171; web_test.exs:117. **Gaps:** deletion records untested; link
records and item amount, frequency, and date untested by marker. VV-RUN-001 P found "Groceries", "Rent", and
"passphrase" absent from a used vault, which is supportive only.

**REQ-123 · Not Verified.** Listen only on 127.0.0.1; reject non-loopback Host; CSRF on every state-changing
request; discard unlocked keys on logout or after 15 minutes idle.
- C1 → web_test.exs:46; end_to_end_test.exs:117; VV-RUN-001 P (127.0.0.1 only).
- C2 → web_test.exs:52; VV-RUN-001 P (421).
- C3 → **partial:** router-wide plug (web.ex:50) and tests on /login and /act/add_value only (web_test.exs:62;
  refusal_log_test.exs:78; def035_test.exs).
- C4 → web_test.exs:74.
- C5 → **violated:** keys are discarded lazily, on the first request after 15 minutes. An unlocked session idle for
  16 minutes is still held in memory (VV-RUN-001 D1). `Sessions` documents this ("on its first use after 15 minutes
  idle"), but the Requirement says "after 15 minutes idle". Possibly a wording ambiguity. → Finding F-02.

The code also accepts Host `localhost:<port>`, which is reasonable but not stated.

**REQ-124 · Indeterminate.** No outbound connections; no remote resources. web_test.exs:105 (a static grep of lib/
and deps); web_test.exs:97 (CSP on GET / only). VV-RUN-001 P: CSP `default-src 'none'` observed; no non-loopback
connection in one snapshot. **Gap:** no network capture over a full session; the CSP is asserted on one page (set
centrally, web.ex:189).

**REQ-125 · Verified (against its recorded interpretation).** "The member who made a proposal, or any current
owner, can withdraw it while pending." The recorded interpretation reads: "The proposer counts while still an owner;
an owner who relinquishes already loses their proposals". exit_test.exs:131-158; randomized_test.exs:208;
http_actions_test.exs:99; sharing_section_test.exs:206; vault_test.exs:154.
**Specification finding (demonstrated, VV-RUN-001 D2):** a proposer removed by an agreed owner change, rather than
by relinquishing, keeps a pending proposal they can no longer withdraw. The remaining owner can still approve it.
The interpretation's premise is false for that path. → Finding F-03.

**REQ-128 · Verified.** The distribution uses visible items and own links: per value and unlinked, counts, per-month
in/out, one-offs, and no evaluation. alignment_test.exs:82-200; randomized_test.exs; frequency_test.exs:125.
Spec note: the rounding mode (half away from zero) is unstated.

**REQ-129 · Indeterminate.** Nine frequency presets with no default; normalized storage; shown wherever the amount
is; legacy values read. frequency_test.exs:58, :84, :91, :171, :210; alignment_test.exs:130, :167.
**Gap:** "shown wherever the amount is shown" is covered for home, item, and export only. Open-ended wording.

**REQ-130 · Indeterminate.** Accounts and debts are member-owned private items under REQ-101..110 and REQ-125;
name and kind fixed. balances_test.exs:18, :29; randomized_test.exs. **Gap:** "fixed" rests only on there being no
edit API. Spec defect: the listed account types omit the 401(k) and IRA types of REQ-149.

**REQ-131 · Verified.** Owners, and nobody else, add dated readings without consent; append-only; in history.
balances_test.exs:38-57; readings_crypto_test.exs:111; balances_web_test.exs:64, :122, :173; randomized_test.exs
readings checks.

**REQ-132 · Verified.** Readers see the latest reading, owners see all, nobody else sees any. balances_test.exs:84;
readings_crypto_test.exs:70; balances_web_test.exs:173; randomized_test.exs readings checks.

**REQ-133 · Indeterminate.** Per-reading keys are sealed to allowed readers, removed on loss of access, and never
given to a tampered-in reader. readings_crypto_test.exs:70, :93, :111, :123, :147. **Gaps:** distinct per-reading
keys are unasserted; a member who becomes an owner after readings exist is untested; loss of access by relinquishing
is untested.

**REQ-134 · Indeterminate.** Accounts and debts are excluded from the distribution and cannot be linked.
balances_test.exs:113; randomized_test.exs. **Gap:** linking a debt is never attempted.

## Balances, cash flow, plans, goals, retirement (REQ-135 to REQ-152)

**REQ-135 · Indeterminate.** Account and debt pages: latest reading and date, owner actions, history for owners, a
month's interest as a fact; home lists them compactly with links and no forms. balances_web_test.exs:54-198;
balances_test.exs:135; ux005_test.exs (exact $129.12). **Gaps:** the home row → page link is unasserted; a debt's
as-of date is unasserted. Spec defect: "no forms on home" is literally false (home has the add-item and add-value
forms); the scope intended is account and debt forms.

**REQ-136 · Verified.** An optional date at add; schedule from it; one-offs on it; irregular has none; stored
protected; undated items work. cash_flow_web_test.exs:60-71; schedule_test.exs:18-37; vault_test.exs:115.

**REQ-137 · Verified.** N weeks = 7N days; months and years on the same day, clamped to the month's end.
schedule_test.exs:13, :18, :23, :43.

**REQ-139 · Indeterminate.** The next sixty days, day by day, with the running balance, marking below-zero days, no
other label. cash_flow_web_test.exs:126-151; ux003_test.exs:109; ux004_test.exs:188; glossary_test.exs:297.
**Gaps:** the 60-day horizon (day 60 in, day 61 out) is untested. Spec defects: it refers to superseded REQ-138;
"day by day" versus the implementation's dated days only.

**REQ-140 · Indeterminate.** Owned money-out items less often than monthly: monthly set-aside and which items.
schedule_test.exs:126-151; cash_flow_web_test.exs:144-146; ux005_test.exs. **Gap:** yearly and every-2/3-month
money-out are not asserted.

**REQ-142 · Verified.** Private named plans with switch-off, planned, and borrow steps from a month; add and remove;
never in real totals. plans_projection_test.exs:75-174; v03_web_test.exs:108-209, :313.
**Test defect:** plans_projection_test.exs:137-144 is vacuous (`|> then(fn _ -> {:error, :invalid_step} end)`
always matches). The clause it seems to target, plan privacy, is covered elsewhere (v03_web_test.exs:108).
→ Finding F-06.

**REQ-143 · Indeterminate.** A plan's 12 months with and without, side by side, including borrowing interest; every
place a plan appears says so. v03_web_test.exs:151-164, :347, :353, :375; plans_projection_test.exs:75, :106.
**Gap:** "every place" is not enumerated; /plans, export, leave, and history are unchecked.

**REQ-144 · Verified.** Mark owned items as depending on an owned income; plans switch them off too; private.
plans_projection_test.exs:99, :177-184; v03_web_test.exs:216-248.

**REQ-145 · Indeterminate.** Debt what-ifs as facts, for anyone who can see the debt; nothing stored; no payment
order. v03_web_test.exs:251-271; plans_projection_test.exs:203-206; ux005_test.exs. **Gaps:** only the owner is
tested (not a member it's shared with); "no payment order suggested" has no test and no observable criterion.

**REQ-146 · Indeterminate.** Private emergency-fund goal; savings cover; progress; no System target.
v03_web_test.exs:280-288; plans_projection_test.exs:214-231. **Gaps:** privacy from other members and absence of a
default target are untested.

**REQ-147 · Verified.** Private set-aside rate on money in linked to own values, with the monthly amount.
v03_web_test.exs:304-309; plans_projection_test.exs:235-262.

**REQ-148 · Indeterminate.** Propose a plan as shared; consent of each named member and every owner; preview; steps
never change. v03_web_test.exs:337-375; plans_projection_test.exs:279-286. **Gaps:** "steps never change" is
untested; multi-owner and multi-member cases are untested.

**REQ-149 · Indeterminate.** 401(k)/IRA accounts with readings under the account rules; never cash.
v04_web_test.exs:85-96, :223; retirement_test.exs:48-59, :187. **Gap:** reading rules (non-owner refusal, hidden
earlier readings) are not tested for retirement types.

**REQ-150 · Indeterminate.** Private optional clearable assumptions; return −5..15%; invalid refused and kept;
nothing prefilled; cleanup. retirement_test.exs:67-133; v04_web_test.exs:100-265. **Gap:** clearing birth year, SS,
and target is untested. Inconsistency: the web treats contribution "0" as clear, while core refuses 0
(retirement_test.exs:113 versus v04_web_test.exs:241).

**REQ-151 · Verified.** Year-by-year balances to January of the retirement year from visible latest balances,
monthly growth and contributions, today's dollars, assumptions stated. retirement_test.exs:138-175;
v04_web_test.exs:107-130.

**REQ-152 · Indeterminate.** Target minus SS; how long it lasts; remains at 100; or covered; nothing scored or
compared with unset figures. retirement_test.exs:208-235; v04_web_test.exs:196, :220. **Gaps:** the "at 100"
sentence is not rendered in any test. Spec conflict: "not compared with any figure the member did not set" versus
REQ-153's ±2 table. → Finding F-01.

## Retirement sensitivity, portability, and interface safeguards (REQ-153 to REQ-166)

**REQ-153 · Indeterminate.** Balance and how long it lasts at return ±2 and age ±2, beside the result; nothing saved.
retirement_test.exs:239, :264; v04_web_test.exs:200, :245. **Gap:** "how long it would last" for the alternatives
is never asserted. Out-of-range alternatives are dropped silently, which the statement doesn't mention.

**REQ-154 · Indeterminate.** No retirement page suggests an investment, product, contribution, return, age, or
target; judgment-word and glossary checks cover every retirement page. v04_web_test.exs:112, :265; glossary_test.exs.
**Gaps:** "suggest" is checked by a phrase list only; prefills are checked for age only. Tension with REQ-153's
±2 alternatives and the example text in field errors.

**REQ-155 · Indeterminate.** The versioned export carries own plans, marks, goals, and assumptions with in-file
references only; nothing belongs to anyone else. import_test.exs:186, :224; exit_test.exs; cp014_web_test.exs:167;
v05_web_test.exs:123. **Gaps:** filtering of marks, plan steps, and links that name non-owned entries is untested.
Spec defect: jointly owned exported items carry the co-owner's ledger entries.

**REQ-156 · Indeterminate.** Bring-in makes everything new and solely owned, remaps references, keeps existing
settings, excludes history, owners, sharing, and shared plans, and tells the member. import_test.exs:237, :314;
v05_web_test.exs:158. **Gaps:** link endpoints and mark targets after remapping are unasserted; absence of old
history is unasserted; the "not brought in" text is unasserted.

**REQ-157 · Verified.** An untrusted file: ≤ 1 MB, JSON, known format and version, every field validated; any
failure brings in nothing and says what and where; no atoms; nothing runs. v05_web_test.exs:233, :264, :318;
import_test.exs:394 (35 cases) and the atom test.

**REQ-158 · Indeterminate.** A preview with counts and names before saving; confirm or cancel; nothing saved on
cancel or leaving. v05_web_test.exs:158, :213; e2e W10. **Gaps:** the goals count is not asserted; the debts line
is not rendered in a test; "leaving the page" is untested, and the pending file survives navigation until the
session ends (sessions.ex:47-55).

**REQ-159 · Verified.** The same file brought in twice by the same member is refused with the earlier date; others
are unaffected. import_test.exs:237, :362; v05_web_test.exs:158; e2e W10.

**REQ-160 · Indeterminate.** Say which cash account (not retirement) a visible money item goes through; change or
clear; private; removed on delete or leave. attach_test.exs:52-151; cp014_web_test.exs:105, :142. **Gaps:**
changing to a different account is untested; the "other" account type is untested; the leave cleanup check is weak.

**REQ-161 · Indeterminate.** Home's next 14 days: first four days with something, a count of more, a link to the
full view; items in date order; running balance with its start and joint caveat. cash_flow_web_test.exs:81;
attach_test.exs:104-151; schedule_test.exs:72-115; ux002_test.exs:29; ux004_test.exs. **Gaps:** the four-day cap,
the "N more days" line, and the link to the full view are untested.

**REQ-162 · Indeterminate.** Twelve months of in and out and month-end cash; debts grow and fall until paid off;
assumptions and caveat. plans_projection_test.exs:49-60; attach_test.exs:141, :155; v03_web_test.exs:94;
ux002_test.exs:29. **Gap:** payoff (a debt reaching zero and stopping) is never exercised.

**REQ-163 · Not Applicable.** State `proposed`, not an accepted Requirement. It stays proposed until DEF-026. The
behaviour is deliberately absent, and the interface says so (cp014_web_test.exs:155).

**REQ-164 · Verified.** Attachments exported where the member owns both; restored on bring-in; version 3; earlier
versions still come in. import_test.exs:186, :331, :342; cp014_web_test.exs:167; v05_web_test.exs:123.

**REQ-165 · Not Verified.** A form sent more than once changes the household at most once; a repeat says it was
already saved; a form that changed nothing may be resent. ux004_test.exs:89, :152; e2e W11.
**Violations (demonstrated, VV-RUN-001 D3):**
- the session remembers only the last 64 claimed form tokens (sessions.ex:69 `@forms_kept 64`), so a form resent
  after 64 later forms is applied again;
- a request without the `_form` field is never deduplicated. A browser always sends it, so only a crafted request
  reaches this path.

Also untested: the in-flight double click (`:busy`), resending after a session ended, and most household-changing
routes (6 tested). → Finding F-04.

**REQ-166 · Indeterminate.** Deleting an item, value, or plan with steps shows what would go, by name, and asks;
going back leaves it; removing a step or link doesn't ask. web_ux_test.exs:95, :146; ux004_test.exs:216;
sharing_section_test.exs:110-113; e2e W7, W11. **Gaps:** deleting a value is untested; "go back" is asserted for
plans only. Confirmation is enforced in the interface, not the handler (a direct POST deletes). Spec note: "by name"
is ambiguous (steps are counted, not named).

---

## Tally

| Result | Count | Requirements |
|---|---|---|
| Verified | 22 | 101, 103, 105, 106, 107, 110, 111, 115, 116, 125, 128, 131, 132, 136, 137, 142, 144, 147, 151, 157, 159, 164 |
| Not Verified | 5 | 102, 112, 117 (specification conflicts); 123, 165 (implementation) |
| Indeterminate | 31 | 108, 114, 118, 119, 120, 121, 122, 124, 129, 130, 133, 134, 135, 139, 140, 143, 145, 146, 148, 149, 150, 152, 153, 154, 155, 156, 158, 160, 161, 162, 166 |
| Not Applicable | 1 | 163 (proposed) |

REQ-001 to REQ-016 govern the project's assurance tooling (`scripts/check`, `scripts/trace`), not the product.
They are outside this system of interest. Their suite (69 tests) passed in REPRO-RUN-018 and is recorded as
tool-qualification evidence only.
