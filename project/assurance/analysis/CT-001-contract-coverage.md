# CT-001: contract test coverage for REQ-188 AC-1

Prepared by ACT-002 on 29 September 2026 for WI-074 (REV-099). REQ-188 AC-1: one set of contract tests, run against both forms' contexts, asserts each acceptance criterion of the Requirements CLM-038 names; the criteria excluded as specific to the local form are recorded with the reason for each.

## How the criteria were sorted

Each of the 324 acceptance criteria of the 57 Requirements CLM-038 names was classed by what decides it: **CORE** (a core rule, the same code in both forms), **PERSIST** (persistence, encryption, what is stored, or a member's view), **WEB** (pages, forms, HTTP, the browser), or **LOCAL** (one device, the vault file, the loopback address). Counts: CORE 180, PERSIST 69, WEB 56, LOCAL 19.

- CORE and PERSIST criteria are asserted by the contract cases in `shared/test/support/contract/*_cases.ex`, which run unchanged against both forms: `app/test/contract_test.exs` (the local form's `FindependenceApp.ContractForm`) and `hosted/test/findependence_hosted/contract_test.exs` (`FindependenceHosted.ContractForm`, PostgreSQL). Storage criteria are asserted on each form's stored sealed state in the vault's shape (`stored/1`) and on every stored value (`stored_bytes/1`).
- WEB criteria need the hosted pages and are WI-075's (REV-099 G1).
- LOCAL criteria are excluded from REQ-188 as its statement allows; each has a hosted counterpart named below.

Result at this commit: 249 of 249 CORE and PERSIST criteria asserted on both forms (251 contract tests pass on each form); one of them, REQ-150 AC-9, is skipped on both because both fail it (DEF-061). Partial coverage is listed in the notes.

## Every criterion

| Requirement | AC | Class | Asserted by, or why not |
|---|---|---|---|
| REQ-101 | AC-1 | CORE | req101_128_cases.ex |
| REQ-101 | AC-2 | CORE | req101_128_cases.ex |
| REQ-101 | AC-3 | CORE | req101_128_cases.ex |
| REQ-101 | AC-4 | CORE | req101_128_cases.ex |
| REQ-103 | AC-1 | CORE | req101_128_cases.ex |
| REQ-103 | AC-2 | CORE | req101_128_cases.ex |
| REQ-103 | AC-3 | PERSIST | req101_128_cases.ex |
| REQ-103 | AC-4 | CORE | req101_128_cases.ex |
| REQ-105 | AC-1 | CORE | req101_128_cases.ex |
| REQ-105 | AC-2 | CORE | req101_128_cases.ex |
| REQ-105 | AC-3 | PERSIST | req101_128_cases.ex |
| REQ-105 | AC-4 | PERSIST | req101_128_cases.ex |
| REQ-106 | AC-1 | CORE | req101_128_cases.ex |
| REQ-106 | AC-2 | WEB | WI-075 (hosted pages) |
| REQ-107 | AC-1 | CORE | req101_128_cases.ex |
| REQ-107 | AC-2 | CORE | req101_128_cases.ex |
| REQ-107 | AC-3 | CORE | req101_128_cases.ex |
| REQ-107 | AC-4 | CORE | req101_128_cases.ex |
| REQ-107 | AC-5 | CORE | req101_128_cases.ex |
| REQ-108 | AC-1 | CORE | req101_128_cases.ex |
| REQ-108 | AC-2 | CORE | req101_128_cases.ex |
| REQ-108 | AC-3 | PERSIST | req101_128_cases.ex |
| REQ-108 | AC-4 | PERSIST | req101_128_cases.ex |
| REQ-108 | AC-5 | PERSIST | req101_128_cases.ex |
| REQ-108 | AC-6 | PERSIST | req101_128_cases.ex |
| REQ-108 | AC-7 | PERSIST | req101_128_cases.ex |
| REQ-110 | AC-1 | CORE | req101_128_cases.ex |
| REQ-110 | AC-2 | PERSIST | req101_128_cases.ex |
| REQ-110 | AC-3 | PERSIST | req101_128_cases.ex |
| REQ-110 | AC-4 | PERSIST | req101_128_cases.ex |
| REQ-110 | AC-5 | PERSIST | req101_128_cases.ex |
| REQ-110 | AC-6 | CORE | req101_128_cases.ex |
| REQ-110 | AC-7 | CORE | req101_128_cases.ex |
| REQ-111 | AC-1 | CORE | req101_128_cases.ex |
| REQ-111 | AC-2 | CORE | req101_128_cases.ex |
| REQ-111 | AC-3 | PERSIST | req101_128_cases.ex |
| REQ-111 | AC-4 | PERSIST | req101_128_cases.ex |
| REQ-114 | AC-1 | PERSIST | req101_128_cases.ex |
| REQ-114 | AC-2 | PERSIST | req101_128_cases.ex |
| REQ-114 | AC-3 | PERSIST | req101_128_cases.ex |
| REQ-114 | AC-4 | PERSIST | req101_128_cases.ex |
| REQ-114 | AC-5 | PERSIST | req101_128_cases.ex; partly: link and unlink after departure are not probed: a member who has left has no session in either form; the page clauses are WI-075's |
| REQ-114 | AC-6 | PERSIST | req101_128_cases.ex |
| REQ-115 | AC-1 | CORE | req101_128_cases.ex |
| REQ-115 | AC-2 | CORE | req101_128_cases.ex |
| REQ-115 | AC-3 | PERSIST | req101_128_cases.ex |
| REQ-115 | AC-4 | CORE | req101_128_cases.ex |
| REQ-115 | AC-5 | CORE | req101_128_cases.ex |
| REQ-115 | AC-6 | CORE | req101_128_cases.ex |
| REQ-116 | AC-1 | CORE | req101_128_cases.ex |
| REQ-116 | AC-2 | CORE | req101_128_cases.ex |
| REQ-118 | AC-1 | LOCAL | excluded: Private/personal key absent from the vault file bytes (hosted analogue REQ-182 AC-1). Hosted counterpart: REQ-181, REQ-182 |
| REQ-118 | AC-2 | LOCAL | excluded: Vault secret box under PBKDF2 with vault iteration count (hosted analogue REQ-182 AC-2). Hosted counterpart: REQ-181, REQ-182 |
| REQ-118 | AC-3 | LOCAL | excluded: Vault setup/create iteration floor and test-only flag (hosted REQ-182 AC-2). Hosted counterpart: REQ-181, REQ-182 |
| REQ-118 | AC-4 | LOCAL | excluded: Per-member salt distinct across vault members and vaults (hosted REQ-182 AC-2). Hosted counterpart: REQ-181, REQ-182 |
| REQ-118 | AC-5 | LOCAL | excluded: Local unlock: wrong passphrase, no session, 401 (hosted REQ-181/182). Hosted counterpart: REQ-181, REQ-182 |
| REQ-118 | AC-6 | LOCAL | excluded: Local unlock failure responses and log line identical (hosted REQ-181 AC-2). Hosted counterpart: REQ-181, REQ-182 |
| REQ-119 | AC-1 | LOCAL | excluded: No attribute in the vault file bytes; hosted analogue is REQ-187 AC-1 (table dump). Hosted counterpart: REQ-187 AC-1 (table dump has no plaintext) |
| REQ-119 | AC-2 | PERSIST | items_cases.ex |
| REQ-119 | AC-3 | PERSIST | req101_128_cases.ex |
| REQ-119 | AC-4 | PERSIST | req101_128_cases.ex |
| REQ-119 | AC-5 | PERSIST | req101_128_cases.ex; partly: the clause about a reader list edited outside the app is asserted per form (hosted domain_test.exs; local tamper_test.exs) |
| REQ-121 | AC-1 | LOCAL | excluded: Links not in vault file plaintext; hosted REQ-187 AC-1. Hosted counterpart: REQ-187 AC-1 (table dump has no plaintext) |
| REQ-121 | AC-2 | LOCAL | excluded: Deletion records not in vault file plaintext; hosted REQ-187 AC-1. Hosted counterpart: REQ-187 AC-1 (table dump has no plaintext) |
| REQ-121 | AC-3 | PERSIST | req101_128_cases.ex; partly: the clause that the personal key is stored only inside the passphrase-protected secret is each form's key storage: REQ-182 (hosted), REQ-118 (local) |
| REQ-122 | AC-1 | LOCAL | excluded: No item attributes in vault file plaintext; hosted analogue REQ-187 AC-1. Hosted counterpart: REQ-187 AC-1 (table dump has no plaintext) |
| REQ-122 | AC-2 | LOCAL | excluded: No value labels in vault file plaintext; hosted analogue REQ-187 AC-1. Hosted counterpart: REQ-187 AC-1 (table dump has no plaintext) |
| REQ-122 | AC-3 | LOCAL | excluded: No links in vault file plaintext; hosted analogue REQ-187 AC-1. Hosted counterpart: REQ-187 AC-1 (table dump has no plaintext) |
| REQ-122 | AC-4 | LOCAL | excluded: No ledger entry details in vault file plaintext; hosted analogue REQ-187 AC-1. Hosted counterpart: REQ-187 AC-1 (table dump has no plaintext) |
| REQ-122 | AC-5 | LOCAL | excluded: No deletion records in vault file plaintext; hosted analogue REQ-187 AC-1. Hosted counterpart: REQ-187 AC-1 (table dump has no plaintext) |
| REQ-123 | AC-1 | LOCAL | excluded: Binds 127.0.0.1 only. Hosted counterpart: REQ-183 (sessions), none for loopback (hosted listens publicly) |
| REQ-123 | AC-2 | LOCAL | excluded: Host header must be loopback+port (421). Hosted counterpart: REQ-183 (sessions), none for loopback (hosted listens publicly) |
| REQ-123 | AC-3 | WEB | WI-075 (hosted pages) |
| REQ-123 | AC-4 | WEB | WI-075 (hosted pages) |
| REQ-123 | AC-5 | WEB | WI-075 (hosted pages) |
| REQ-124 | AC-1 | WEB | WI-075 (hosted pages) |
| REQ-124 | AC-2 | WEB | WI-075 (hosted pages) |
| REQ-125 | AC-1 | CORE | req101_128_cases.ex |
| REQ-125 | AC-2 | CORE | req101_128_cases.ex |
| REQ-125 | AC-3 | CORE | req101_128_cases.ex |
| REQ-125 | AC-4 | CORE | req101_128_cases.ex |
| REQ-128 | AC-1 | CORE | req101_128_cases.ex |
| REQ-128 | AC-2 | CORE | req101_128_cases.ex |
| REQ-128 | AC-3 | CORE | req101_128_cases.ex |
| REQ-128 | AC-4 | CORE | req101_128_cases.ex |
| REQ-128 | AC-5 | CORE | req101_128_cases.ex |
| REQ-128 | AC-6 | CORE | req101_128_cases.ex |
| REQ-128 | AC-7 | CORE | req101_128_cases.ex |
| REQ-128 | AC-8 | CORE | req101_128_cases.ex; partly: only the unrecognised-frequency half: the contexts refuse a missing frequency, so an item without one can't be made through them |
| REQ-128 | AC-9 | CORE | req101_128_cases.ex |
| REQ-129 | AC-1 | WEB | WI-075 (hosted pages) |
| REQ-129 | AC-2 | CORE | req129_145_cases.ex; partly: only the no-choice case: refusing an unknown choice is the transport's (WI-075) |
| REQ-129 | AC-3 | CORE | req129_145_cases.ex |
| REQ-129 | AC-4 | PERSIST | req129_145_cases.ex |
| REQ-129 | AC-5 | LOCAL | excluded: Frequency not in vault file plaintext; hosted REQ-187 AC-1. Hosted counterpart: REQ-187 AC-1 (table dump has no plaintext) |
| REQ-129 | AC-6 | WEB | WI-075 (hosted pages) |
| REQ-129 | AC-7 | CORE | req129_145_cases.ex |
| REQ-131 | AC-1 | CORE | req129_145_cases.ex |
| REQ-131 | AC-2 | CORE | req129_145_cases.ex |
| REQ-131 | AC-3 | CORE | req129_145_cases.ex |
| REQ-131 | AC-4 | CORE | req129_145_cases.ex |
| REQ-131 | AC-5 | PERSIST | req129_145_cases.ex |
| REQ-131 | AC-6 | CORE | req129_145_cases.ex |
| REQ-132 | AC-1 | PERSIST | req129_145_cases.ex |
| REQ-132 | AC-2 | PERSIST | req129_145_cases.ex |
| REQ-132 | AC-3 | PERSIST | req129_145_cases.ex |
| REQ-133 | AC-1 | PERSIST | req129_145_cases.ex; partly: shown by separate boxes and key maps per reading and a grantee who opens the latest reading but not the earlier one |
| REQ-133 | AC-2 | PERSIST | req129_145_cases.ex |
| REQ-133 | AC-3 | PERSIST | req129_145_cases.ex |
| REQ-133 | AC-4 | PERSIST | req129_145_cases.ex |
| REQ-133 | AC-5 | PERSIST | req129_145_cases.ex |
| REQ-133 | AC-6 | PERSIST | hosted/test/findependence_hosted/domain_test.exs (a reader written into storage) and, for the local form, app/test/tamper_test.exs |
| REQ-134 | AC-1 | CORE | req129_145_cases.ex |
| REQ-134 | AC-2 | CORE | req129_145_cases.ex |
| REQ-136 | AC-1 | CORE | req129_145_cases.ex |
| REQ-136 | AC-2 | WEB | WI-075 (hosted pages) |
| REQ-136 | AC-3 | CORE | req129_145_cases.ex |
| REQ-136 | AC-4 | CORE | req129_145_cases.ex |
| REQ-136 | AC-5 | CORE | req129_145_cases.ex |
| REQ-136 | AC-6 | LOCAL | excluded: Date not in vault file plaintext; hosted REQ-187 AC-1. Hosted counterpart: REQ-187 AC-1 (table dump has no plaintext) |
| REQ-136 | AC-7 | CORE | req129_145_cases.ex |
| REQ-137 | AC-1 | CORE | req129_145_cases.ex |
| REQ-137 | AC-2 | CORE | req129_145_cases.ex |
| REQ-137 | AC-3 | CORE | req129_145_cases.ex |
| REQ-137 | AC-4 | CORE | req129_145_cases.ex |
| REQ-140 | AC-1 | CORE | req129_145_cases.ex |
| REQ-140 | AC-2 | CORE | req129_145_cases.ex |
| REQ-140 | AC-3 | CORE | req129_145_cases.ex |
| REQ-140 | AC-4 | CORE | req129_145_cases.ex |
| REQ-140 | AC-5 | CORE | req129_145_cases.ex |
| REQ-140 | AC-6 | CORE | req129_145_cases.ex |
| REQ-140 | AC-7 | CORE | req129_145_cases.ex |
| REQ-140 | AC-8 | CORE | req129_145_cases.ex |
| REQ-140 | AC-9 | CORE | req129_145_cases.ex |
| REQ-140 | AC-10 | CORE | req129_145_cases.ex |
| REQ-142 | AC-1 | CORE | req129_145_cases.ex |
| REQ-142 | AC-2 | CORE | req129_145_cases.ex |
| REQ-142 | AC-3 | CORE | req129_145_cases.ex |
| REQ-142 | AC-4 | CORE | req129_145_cases.ex |
| REQ-142 | AC-5 | CORE | req129_145_cases.ex |
| REQ-142 | AC-6 | CORE | req129_145_cases.ex |
| REQ-142 | AC-7 | PERSIST | req129_145_cases.ex |
| REQ-142 | AC-8 | CORE | req129_145_cases.ex |
| REQ-143 | AC-1 | CORE | req129_145_cases.ex |
| REQ-143 | AC-2 | CORE | req129_145_cases.ex |
| REQ-143 | AC-3 | WEB | WI-075 (hosted pages) |
| REQ-144 | AC-1 | CORE | req129_145_cases.ex |
| REQ-144 | AC-2 | CORE | req129_145_cases.ex |
| REQ-144 | AC-3 | CORE | req129_145_cases.ex |
| REQ-144 | AC-4 | CORE | req129_145_cases.ex |
| REQ-144 | AC-5 | PERSIST | req129_145_cases.ex |
| REQ-145 | AC-1 | CORE | req129_145_cases.ex |
| REQ-145 | AC-2 | CORE | req129_145_cases.ex |
| REQ-145 | AC-3 | CORE | req129_145_cases.ex |
| REQ-145 | AC-4 | CORE | req129_145_cases.ex |
| REQ-145 | AC-5 | PERSIST | req129_145_cases.ex |
| REQ-145 | AC-6 | WEB | WI-075 (hosted pages) |
| REQ-145 | AC-7 | WEB | WI-075 (hosted pages) |
| REQ-145 | AC-8 | WEB | WI-075 (hosted pages) |
| REQ-146 | AC-1 | CORE | req146_157_cases.ex |
| REQ-146 | AC-2 | CORE | req146_157_cases.ex |
| REQ-146 | AC-3 | CORE | req146_157_cases.ex |
| REQ-146 | AC-4 | PERSIST | req146_157_cases.ex |
| REQ-146 | AC-5 | WEB | WI-075 (hosted pages) |
| REQ-146 | AC-6 | WEB | WI-075 (hosted pages) |
| REQ-147 | AC-1 | CORE | req146_157_cases.ex |
| REQ-147 | AC-2 | CORE | req146_157_cases.ex |
| REQ-147 | AC-3 | CORE | req146_157_cases.ex |
| REQ-147 | AC-4 | PERSIST | req146_157_cases.ex |
| REQ-148 | AC-1 | CORE | req146_157_cases.ex |
| REQ-148 | AC-2 | CORE | req146_157_cases.ex |
| REQ-148 | AC-3 | CORE | req146_157_cases.ex |
| REQ-148 | AC-4 | CORE | req146_157_cases.ex |
| REQ-148 | AC-5 | PERSIST | req146_157_cases.ex |
| REQ-148 | AC-6 | CORE | req146_157_cases.ex |
| REQ-149 | AC-1 | CORE | req146_157_cases.ex |
| REQ-149 | AC-2 | PERSIST | req146_157_cases.ex |
| REQ-149 | AC-3 | CORE | req146_157_cases.ex |
| REQ-149 | AC-4 | CORE | req146_157_cases.ex |
| REQ-149 | AC-5 | CORE | req146_157_cases.ex |
| REQ-149 | AC-6 | PERSIST | req146_157_cases.ex |
| REQ-149 | AC-7 | PERSIST | req146_157_cases.ex; partly: the clause about a reader written in without the app is asserted per form (as REQ-133 AC-6) |
| REQ-149 | AC-8 | CORE | req146_157_cases.ex |
| REQ-149 | AC-9 | CORE | req146_157_cases.ex |
| REQ-150 | AC-1 | CORE | req146_157_cases.ex |
| REQ-150 | AC-2 | PERSIST | req146_157_cases.ex |
| REQ-150 | AC-3 | CORE | req146_157_cases.ex |
| REQ-150 | AC-4 | CORE | req146_157_cases.ex |
| REQ-150 | AC-5 | CORE | req146_157_cases.ex |
| REQ-150 | AC-6 | CORE | req146_157_cases.ex |
| REQ-150 | AC-7 | CORE | req146_157_cases.ex; partly: out-of-range amounts are refused by the core as :invalid_retirement without naming a field; the field-level clause is the transport's (WI-075) |
| REQ-150 | AC-8 | WEB | WI-075 (hosted pages) |
| REQ-150 | AC-9 | PERSIST | req146_157_cases.ex; skipped on both forms (DEF-061) |
| REQ-151 | AC-1 | CORE | req146_157_cases.ex |
| REQ-151 | AC-2 | CORE | req146_157_cases.ex |
| REQ-151 | AC-3 | CORE | req146_157_cases.ex |
| REQ-151 | AC-4 | CORE | req146_157_cases.ex |
| REQ-151 | AC-5 | WEB | WI-075 (hosted pages) |
| REQ-153 | AC-1 | CORE | req146_157_cases.ex |
| REQ-153 | AC-2 | CORE | req146_157_cases.ex |
| REQ-153 | AC-3 | WEB | WI-075 (hosted pages) |
| REQ-153 | AC-4 | CORE | req146_157_cases.ex |
| REQ-154 | AC-1 | WEB | WI-075 (hosted pages) |
| REQ-154 | AC-2 | WEB | WI-075 (hosted pages) |
| REQ-154 | AC-3 | WEB | WI-075 (hosted pages) |
| REQ-154 | AC-4 | WEB | WI-075 (hosted pages) |
| REQ-155 | AC-1 | CORE | req146_157_cases.ex |
| REQ-155 | AC-2 | CORE | req146_157_cases.ex |
| REQ-155 | AC-3 | CORE | req146_157_cases.ex |
| REQ-155 | AC-4 | CORE | req146_157_cases.ex |
| REQ-155 | AC-5 | CORE | req146_157_cases.ex |
| REQ-155 | AC-6 | CORE | req146_157_cases.ex |
| REQ-155 | AC-7 | CORE | req146_157_cases.ex |
| REQ-155 | AC-8 | CORE | req146_157_cases.ex |
| REQ-156 | AC-1 | CORE | req146_157_cases.ex |
| REQ-156 | AC-2 | CORE | req146_157_cases.ex |
| REQ-156 | AC-3 | CORE | req146_157_cases.ex |
| REQ-156 | AC-4 | CORE | req146_157_cases.ex |
| REQ-156 | AC-5 | CORE | req146_157_cases.ex |
| REQ-156 | AC-6 | CORE | req146_157_cases.ex |
| REQ-156 | AC-7 | CORE | req146_157_cases.ex |
| REQ-156 | AC-8 | CORE | req146_157_cases.ex |
| REQ-156 | AC-9 | WEB | WI-075 (hosted pages) |
| REQ-156 | AC-10 | CORE | req146_157_cases.ex |
| REQ-157 | AC-1 | WEB | WI-075 (hosted pages) |
| REQ-157 | AC-2 | CORE | req146_157_cases.ex |
| REQ-157 | AC-3 | CORE | req146_157_cases.ex |
| REQ-157 | AC-4 | CORE | req146_157_cases.ex |
| REQ-157 | AC-5 | CORE | req146_157_cases.ex |
| REQ-157 | AC-6 | CORE | req146_157_cases.ex |
| REQ-157 | AC-7 | CORE | req146_157_cases.ex |
| REQ-159 | AC-1 | PERSIST | req159_174_cases.ex |
| REQ-159 | AC-2 | PERSIST | req159_174_cases.ex |
| REQ-159 | AC-3 | PERSIST | req159_174_cases.ex |
| REQ-160 | AC-1 | CORE | req159_174_cases.ex |
| REQ-160 | AC-2 | CORE | req159_174_cases.ex |
| REQ-160 | AC-3 | CORE | req159_174_cases.ex |
| REQ-160 | AC-4 | CORE | req159_174_cases.ex |
| REQ-160 | AC-5 | CORE | req159_174_cases.ex |
| REQ-160 | AC-6 | PERSIST | req159_174_cases.ex |
| REQ-160 | AC-7 | PERSIST | req159_174_cases.ex |
| REQ-160 | AC-8 | PERSIST | req159_174_cases.ex |
| REQ-161 | AC-1 | WEB | WI-075 (hosted pages) |
| REQ-161 | AC-2 | WEB | WI-075 (hosted pages) |
| REQ-161 | AC-3 | WEB | WI-075 (hosted pages) |
| REQ-161 | AC-4 | WEB | WI-075 (hosted pages) |
| REQ-161 | AC-5 | CORE | req159_174_cases.ex |
| REQ-161 | AC-6 | CORE | req159_174_cases.ex |
| REQ-161 | AC-7 | CORE | req159_174_cases.ex |
| REQ-161 | AC-8 | WEB | WI-075 (hosted pages) |
| REQ-161 | AC-9 | WEB | WI-075 (hosted pages) |
| REQ-162 | AC-1 | CORE | req159_174_cases.ex |
| REQ-162 | AC-2 | CORE | req159_174_cases.ex |
| REQ-162 | AC-3 | CORE | req159_174_cases.ex |
| REQ-162 | AC-4 | CORE | req159_174_cases.ex |
| REQ-162 | AC-5 | CORE | req159_174_cases.ex |
| REQ-162 | AC-6 | CORE | req159_174_cases.ex |
| REQ-162 | AC-7 | WEB | WI-075 (hosted pages) |
| REQ-162 | AC-8 | WEB | WI-075 (hosted pages) |
| REQ-164 | AC-1 | CORE | req159_174_cases.ex |
| REQ-164 | AC-2 | CORE | req159_174_cases.ex |
| REQ-164 | AC-3 | CORE | req159_174_cases.ex |
| REQ-164 | AC-4 | CORE | req159_174_cases.ex |
| REQ-165 | AC-1 | WEB | WI-075 (hosted pages) |
| REQ-165 | AC-2 | WEB | WI-075 (hosted pages) |
| REQ-165 | AC-3 | WEB | WI-075 (hosted pages) |
| REQ-165 | AC-4 | WEB | WI-075 (hosted pages) |
| REQ-165 | AC-5 | WEB | WI-075 (hosted pages) |
| REQ-166 | AC-1 | WEB | WI-075 (hosted pages) |
| REQ-166 | AC-2 | WEB | WI-075 (hosted pages) |
| REQ-166 | AC-3 | WEB | WI-075 (hosted pages) |
| REQ-166 | AC-4 | WEB | WI-075 (hosted pages) |
| REQ-166 | AC-5 | WEB | WI-075 (hosted pages) |
| REQ-166 | AC-6 | WEB | WI-075 (hosted pages) |
| REQ-167 | AC-1 | PERSIST | req159_174_cases.ex |
| REQ-167 | AC-2 | PERSIST | req159_174_cases.ex |
| REQ-167 | AC-3 | PERSIST | req159_174_cases.ex |
| REQ-167 | AC-4 | PERSIST | req159_174_cases.ex |
| REQ-167 | AC-5 | PERSIST | req159_174_cases.ex; partly: the page clause is WI-075's; the context part (a hidden item reads as a missing one) is asserted |
| REQ-167 | AC-6 | PERSIST | req159_174_cases.ex |
| REQ-168 | AC-1 | CORE | req159_174_cases.ex |
| REQ-168 | AC-2 | CORE | req159_174_cases.ex |
| REQ-168 | AC-3 | CORE | req159_174_cases.ex |
| REQ-168 | AC-4 | PERSIST | req159_174_cases.ex |
| REQ-168 | AC-5 | PERSIST | req159_174_cases.ex; partly: shown as the other member's view holding no record of the links; undecryptability needs that member's private key |
| REQ-169 | AC-1 | CORE | req159_174_cases.ex |
| REQ-169 | AC-2 | CORE | req159_174_cases.ex |
| REQ-169 | AC-3 | CORE | req159_174_cases.ex |
| REQ-169 | AC-4 | CORE | req159_174_cases.ex |
| REQ-169 | AC-5 | CORE | req159_174_cases.ex |
| REQ-169 | AC-6 | CORE | req159_174_cases.ex |
| REQ-169 | AC-7 | CORE | req159_174_cases.ex |
| REQ-169 | AC-8 | CORE | req159_174_cases.ex |
| REQ-169 | AC-9 | CORE | req159_174_cases.ex |
| REQ-170 | AC-1 | LOCAL | excluded: Ledger not in vault file plaintext; hosted REQ-187 AC-1. Hosted counterpart: REQ-187 AC-1 (table dump has no plaintext) |
| REQ-170 | AC-2 | PERSIST | req159_174_cases.ex |
| REQ-170 | AC-3 | PERSIST | req159_174_cases.ex |
| REQ-170 | AC-4 | PERSIST | req159_174_cases.ex |
| REQ-170 | AC-5 | PERSIST | req159_174_cases.ex |
| REQ-170 | AC-6 | PERSIST | req159_174_cases.ex; partly: a member written into storage without the app: asserted per form (as REQ-133 AC-6) |
| REQ-171 | AC-1 | CORE | req159_174_cases.ex |
| REQ-171 | AC-2 | CORE | req159_174_cases.ex |
| REQ-171 | AC-3 | PERSIST | req159_174_cases.ex |
| REQ-171 | AC-4 | PERSIST | req159_174_cases.ex |
| REQ-171 | AC-5 | CORE | req159_174_cases.ex |
| REQ-172 | AC-1 | WEB | WI-075 (hosted pages) |
| REQ-172 | AC-2 | WEB | WI-075 (hosted pages) |
| REQ-172 | AC-3 | WEB | WI-075 (hosted pages) |
| REQ-172 | AC-4 | WEB | WI-075 (hosted pages) |
| REQ-172 | AC-5 | WEB | WI-075 (hosted pages) |
| REQ-172 | AC-6 | WEB | WI-075 (hosted pages) |
| REQ-172 | AC-7 | WEB | WI-075 (hosted pages) |
| REQ-173 | AC-1 | WEB | WI-075 (hosted pages) |
| REQ-173 | AC-2 | WEB | WI-075 (hosted pages) |
| REQ-173 | AC-3 | CORE | req159_174_cases.ex |
| REQ-173 | AC-4 | WEB | WI-075 (hosted pages) |
| REQ-173 | AC-5 | WEB | WI-075 (hosted pages) |
| REQ-174 | AC-1 | CORE | req159_174_cases.ex |
| REQ-174 | AC-2 | CORE | req159_174_cases.ex |
| REQ-174 | AC-3 | CORE | req159_174_cases.ex; partly: asserted as a count of months; the years-and-months wording is the page's (WI-075) |
| REQ-174 | AC-4 | CORE | req159_174_cases.ex |
| REQ-174 | AC-5 | CORE | req159_174_cases.ex |
| REQ-174 | AC-6 | WEB | WI-075 (hosted pages) |
| REQ-174 | AC-7 | WEB | WI-075 (hosted pages) |
