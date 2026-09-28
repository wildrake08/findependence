# VV-002: Requirement audit against acceptance criteria

Prepared by ACT-002 on 28 September 2026, on branch `findependence/vv-findings` after WI-059 (commit bca1415 and its record). Companion to [VV-001](VV-001-system-verification-validation.md), whose findings F-05 (untested clauses) and F-08 (no acceptance criteria) this closes. Analysis and evidence at proposal level; it changes no statement.

## Method

- **Criteria.** Four delegated agents (WI-057, batches A to D) wrote acceptance criteria for every accepted Requirement: observable conditions that together are exactly what the statement requires. Where a statement uses a vague word, the criterion states the reading; ACT-001 ratified those readings in REV-070. The criteria are now in each Requirement's record (`acceptance_criteria`), with who added them and under what authority.
- **Tests.** For every criterion without an asserting test, the agents wrote one (core 75, app 59), and showed it fails when the property is broken (143 deliberate breaks: A 24, B 41, C 48, D 30; all caught except two explained cases). ACT-002 added the tests for the defects found on the way (WI-058, WI-059). Tests that exposed a defect were not kept until the defect was repaired.
- **Evidence.** Each criterion cites the tests that assert it as `path:line`. All 693 citations were checked mechanically against the current files: 605 point at unchanged lines, 86 were re-anchored after later edits moved them (their content is unchanged), and 2 were confirmed by name.
- **Results.** Verified: every criterion has a passing test that asserts it (core 200, app 331 at this commit, each run at least twice). Indeterminate: a criterion needs something tests here can't give. No Requirement is Not Verified.

## Tally

| | VV-001 (9e84fa8) | VV-002 (now) |
|---|---|---|
| Accepted Requirements | 58 | 58 |
| Verified | 22 | 57 |
| Not Verified | 5 | 0 |
| Indeterminate | 31 | 1 |
| Acceptance criteria | none | 330 |

REQ-163 stays out of scope (`proposed`). REQ-001 to REQ-016 govern the assurance tooling, not the product.

**The one Indeterminate:** REQ-158 AC-4, that choosing *Bring it in* on the preview works in a browser. It is tested with the background fetches a browser makes (the tab icon, requests marked `Sec-Fetch-Dest: image`), but not in a headed browser, which is the case DEF-046 showed matters. A one-minute check during WALKTHROUGH-001 resolves it.

**What moved since VV-001:** eight Requirements were superseded by corrected wording (REQ-167 to REQ-174, DEF-038); REQ-123, REQ-125, and REQ-165 were repaired (DEF-039..DEF-041, DEF-051); REQ-157's hand entry now follows the file's rules (DEF-049); REQ-143, REQ-158, and REQ-162 were repaired (DEF-046..DEF-048); REQ-146 lost its example goal (REV-070).

## Results

| Requirement | Result | Criteria | Batch |
|---|---|---|---|
| REQ-101 | Verified | 4 | A |
| REQ-103 | Verified | 4 | A |
| REQ-105 | Verified | 4 | A |
| REQ-106 | Verified | 2 | A |
| REQ-107 | Verified | 5 | A |
| REQ-108 | Verified | 7 | A |
| REQ-110 | Verified | 7 | A |
| REQ-111 | Verified | 4 | A |
| REQ-114 | Verified | 6 | A |
| REQ-115 | Verified | 6 | A |
| REQ-116 | Verified | 2 | A |
| REQ-118 | Verified | 6 | B |
| REQ-119 | Verified | 5 | B |
| REQ-121 | Verified | 3 | B |
| REQ-122 | Verified | 5 | B |
| REQ-123 | Verified | 5 | B |
| REQ-124 | Verified | 2 | B |
| REQ-125 | Verified | 4 | A |
| REQ-128 | Verified | 9 | A |
| REQ-129 | Verified | 7 | B |
| REQ-131 | Verified | 6 | B |
| REQ-132 | Verified | 3 | B |
| REQ-133 | Verified | 6 | B |
| REQ-134 | Verified | 2 | A |
| REQ-136 | Verified | 7 | C |
| REQ-137 | Verified | 4 | C |
| REQ-140 | Verified | 10 | C |
| REQ-142 | Verified | 8 | C |
| REQ-143 | Verified | 3 | C |
| REQ-144 | Verified | 5 | C |
| REQ-145 | Verified | 8 | C |
| REQ-146 | Verified | 6 | C |
| REQ-147 | Verified | 4 | C |
| REQ-148 | Verified | 6 | C |
| REQ-149 | Verified | 9 | D |
| REQ-150 | Verified | 9 | D |
| REQ-151 | Verified | 5 | D |
| REQ-153 | Verified | 4 | D |
| REQ-154 | Verified | 4 | D |
| REQ-155 | Verified | 8 | D |
| REQ-156 | Verified | 10 | D |
| REQ-157 | Verified | 7 | D |
| REQ-158 | Indeterminate | 6 | D |
| REQ-159 | Verified | 3 | D |
| REQ-160 | Verified | 8 | C |
| REQ-161 | Verified | 9 | C |
| REQ-162 | Verified | 8 | C |
| REQ-164 | Verified | 4 | D |
| REQ-165 | Verified | 5 | B |
| REQ-166 | Verified | 6 | B |
| REQ-167 | Verified | 6 | A |
| REQ-168 | Verified | 5 | A |
| REQ-169 | Verified | 9 | A |
| REQ-170 | Verified | 6 | B |
| REQ-171 | Verified | 5 | B |
| REQ-172 | Verified | 7 | C |
| REQ-173 | Verified | 5 | C |
| REQ-174 | Verified | 7 | D |

## Criteria and evidence

### REQ-101 · Verified

- **AC-1** Every item, of every kind (money in or out, value, account, debt, shared plan), has a non-empty owner set when created: its creator.  
  Evidence: `core/test/household_test.exs:22` an item starts owned by its creator; `core/test/vv_f05_a_test.exs:46` every kind of item starts owned by its creator
- **AC-2** Every owner is a household member: a non-member can't create an item or be proposed as an owner.  
  Evidence: `core/test/household_test.exs:30` non-members can neither create items nor be made owners; `core/test/randomized_test.exs:299` owner set non-empty and all members after every step; `core/test/vv_f05_a_test.exs:46` non-member owner set refused for every kind
- **AC-3** A proposal to make an item's owner set empty is refused, for every kind of item.  
  Evidence: `core/test/household_test.exs:26` an empty owner set is rejected; `core/test/vv_f05_a_test.exs:46` empty owner set refused for every kind
- **AC-4** No operation leaves an item without owners: the last owner can't relinquish it or leave the household while owning it.  
  Evidence: `core/test/randomized_test.exs:299` checked after every step of 2000 seeded sequences; `core/test/exit_test.exs:21` the last owner cannot relinquish; `core/test/vv_f05_a_test.exs:46` last owner can't relinquish any kind, and can't leave

*Notes:* Interpretation: 'economic item' means every item in the household, including values, accounts, debts, and shared plans (App. A spec note). 'Rejected' means the operation returns an error and the household is unchanged.

### REQ-103 · Verified

- **AC-1** Only an owner can create a grant: a grantee, an unrelated member, or a non-member proposing one is refused and nothing is pending.  
  Evidence: `core/test/household_test.exs:54` only an owner can grant; `core/test/vv_f05_a_test.exs:61` a grantee, an unrelated member, and a non-member can neither create nor revoke a grant
- **AC-2** Only an owner can revoke a grant: a grantee (even of their own grant), an unrelated member, or a non-member is refused and the grant stays.  
  Evidence: `core/test/household_test.exs:73` any single owner can revoke; the grantee and non-owners cannot; `core/test/randomized_test.exs:361` every revocation was by one current owner; `core/test/vv_f05_a_test.exs:61` grantee, unrelated member, non-member can't revoke
- **AC-3** On a jointly owned item a grant takes effect only once every current owner has consented; with a single owner it takes effect at once.  
  Evidence: `core/test/household_test.exs:58` a sole owner's grant takes effect at once; `core/test/household_test.exs:64` a grant on a joint item needs every owner's consent; `core/test/randomized_test.exs:356` every grant consented by every owner at that moment; `core/test/vv_f05_a_test.exs:75` with three owners a grant waits for the last one
- **AC-4** Any single owner of a jointly owned item can revoke a grant alone.  
  Evidence: `core/test/household_test.exs:73` :b revokes alone; `core/test/vv_f05_a_test.exs:75` each of three owners revokes alone

*Notes:* App. A minor gap (an unrelated non-owner's revoke tested only by the randomized test) is closed by vv_f05_a_test.exs:61.

### REQ-105 · Verified

- **AC-1** Each ownership change (an agreed owner change, a relinquishment), grant, and revocation (including a grant removed when its grantee leaves) adds an entry to the item's history.  
  Evidence: `core/test/household_test.exs:121` every change is recorded with who consented; `core/test/exit_test.exs:13` relinquishment recorded; `core/test/exit_test.exs:93` leaving removes held grants (recorded)
- **AC-2** The history is complete: replaying it alone reproduces the item's current owners and grantees.  
  Evidence: `core/test/randomized_test.exs:294` ledger/state match after every step
- **AC-3** Append-only: while the item exists, earlier entries are never changed or removed.  
  Evidence: `core/test/randomized_test.exs:323` the old ledger is a prefix of the new one
- **AC-4** Every current owner, including one who became an owner later, can read the whole history.  
  Evidence: `core/test/household_test.exs:121` :b reads the full ledger; `core/test/randomized_test.exs:309` ledger readable by every current owner; `app/test/vault_test.exs:106` a new owner reads entries made before they joined

*Notes:* The statement requires owners to be able to read, not that others can't; that restriction is REQ-120's. Deletion removes the history (REQ-108); read as REQ-108's exception to append-only (App. A spec note).

### REQ-106 · Verified

- **AC-1** Every aggregate the core computes for a member (sums, the value distribution, the projection, the day-by-day cash flow, the retirement projection) counts only items visible to that member.  
  Evidence: `core/test/household_test.exs:145` each member's total counts only what they can see; `core/test/randomized_test.exs:313` View.sum equals the sum over the ledger-replayed visible items; `core/test/alignment_test.exs:200` only the requester's visible items and own links count; `core/test/randomized_test.exs:510` distribution recomputed independently; `core/test/plans_projection_test.exs:67` projection: only what the member can see; `core/test/schedule_test.exs:101` cash flow: other members' accounts don't count; `core/test/retirement_test.exs:175` only the retirement accounts the member can see
- **AC-2** Every household-level page of the interface is identical, apart from per-request form tokens, whether or not other members hold entries invisible to the member (items, a value, a link, an account and a debt with readings, a plan, a grant to a third member).  
  Evidence: `app/test/vv_f05_a_test.exs:106` another member's private entries change none of a member's household pages

*Notes:* Interpretation: 'household-level view' means every core function that aggregates over the household, and every interface page not about one thing: /, /next-60-days, /ahead, /plans, /retirement, /goals, /leave, /export, /export.json, /balances/new. 'No totals leak' is made observable as AC-2: the pages don't change at all. AC-2 is shown for one set of entry kinds, not proved for all.

### REQ-107 · Verified

- **AC-1** A change to an item's owner set applies only once every current owner has consented, including owners added while it waited; a non-owner's consent is refused.  
  Evidence: `core/test/household_test.exs:88` a change to a joint item waits for all owners; `core/test/household_test.exs:97` needs the consent of owners added while it waited; `core/test/randomized_test.exs:343` every owner change consented by every owner at that moment
- **AC-2** Any owner can remove themselves without anyone's consent while another owner remains.  
  Evidence: `core/test/exit_test.exs:13` a joint owner leaves an item without the other's consent
- **AC-3** That exception removes only the acting owner: removing anyone else needs every owner.  
  Evidence: `core/test/exit_test.exs:27` removing someone else still needs every owner; `core/test/randomized_test.exs:379` each relinquishment removes only its actor, never the last owner
- **AC-4** The last owner can't remove themselves.  
  Evidence: `core/test/exit_test.exs:21` the last owner cannot relinquish
- **AC-5** No member can add themselves as an owner: a non-owner, a grantee, or a non-member proposing an owner set that includes themselves is refused.  
  Evidence: `core/test/household_test.exs:84` no member can add themselves; `core/test/vv_f05_a_test.exs:92` a grantee or a non-member can't propose making themselves an owner

*Notes:* REQ-115 and REQ-148 add the joiner's own consent for values and shared plans; that is an additional condition, not an exception to REQ-107. Test descriptions in household_test.exs still cite the superseded REQ-104.

### REQ-108 · Verified

- **AC-1** A sole owner deletes an item without anyone else's consent.  
  Evidence: `core/test/exit_test.exs:43` sole owner deletes; `core/test/balances_test.exs:29` an account or debt deleted by its owner
- **AC-2** A joint owner's deletion is refused.  
  Evidence: `core/test/exit_test.exs:55` a joint owner cannot delete
- **AC-3** After deletion the item and its grants are gone: nobody, including former grantees, can see it.  
  Evidence: `core/test/exit_test.exs:43` former grantee can't see it; `core/test/balances_test.exs:29` the item is no longer in the household
- **AC-4** Its pending proposals are removed: none is listed, none can be agreed to or withdrawn, and none returns if the id is used again. This includes an invitation to a sole-owned value and a grant left pending from joint ownership.  
  Evidence: `core/test/vv_f05_a_test.exs:105` deleting a sole-owned value removes its pending invitation; `core/test/vv_f05_a_test.exs:122` a pending grant left from joint ownership goes
- **AC-5** Its history is removed.  
  Evidence: `core/test/exit_test.exs:43` Ledger.read not_found and no ledger kept; `core/test/randomized_test.exs:288` ledger and items cover the same ids
- **AC-6** A deletion record containing exactly the item id and a sequence number is kept.  
  Evidence: `core/test/exit_test.exs:43` deletions == [%{seq: 1, item_id: :solo}]; `core/test/randomized_test.exs:388` every vanished item has a deletion record for its sole owner; `app/test/vault_test.exs:133` the record survives encryption as %{seq: 1, item_id: v1}
- **AC-7** Only the deleter can read the record.  
  Evidence: `core/test/exit_test.exs:43` another member's deletions are empty; `app/test/vault_test.exs:133` deletion records private to their member; `app/test/crypto_properties_test.exs:126` another member's secrets can't open the personal record

*Notes:* App. A gap C5 (pending proposals) is closed by vv_f05_a_test.exs:105 and :122. Readings and links of a deleted item also go, but those are REQ-131 and ASM-018, not this statement.

### REQ-110 · Verified

- **AC-1** A member who owns no items leaves without anyone else's consent.  
  Evidence: `core/test/exit_test.exs:85` then leaves unilaterally
- **AC-2** Leaving removes their membership.  
  Evidence: `core/test/exit_test.exs:85` refute :b in members; `core/test/vv_f05_a_test.exs:153` refute :a in members
- **AC-3** Leaving removes every grant they hold.  
  Evidence: `core/test/exit_test.exs:93` leaving removes held grants (recorded); `core/test/randomized_test.exs:422` a departed member holds no grant
- **AC-4** Leaving removes every pending proposal that would grant to them.  
  Evidence: `core/test/exit_test.exs:93` the pending grant to the leaver is gone; `core/test/randomized_test.exs:428` no proposal names a departed member
- **AC-5** Leaving removes every pending proposal that would make them an owner (a value invitation, an owner change on a joint item), and no other proposal.  
  Evidence: `core/test/vv_f05_a_test.exs:138` leaving drops every pending proposal that would make the leaver an owner, and no other; `core/test/randomized_test.exs:428` no proposal names a departed member
- **AC-6** A member who still owns items, jointly or solely (an item or a value), is refused.  
  Evidence: `core/test/exit_test.exs:85` a joint owner is refused; `core/test/vv_f05_a_test.exs:153` a sole owner of an item and a value is refused
- **AC-7** Once they relinquish, transfer, or delete what they own, they can leave.  
  Evidence: `core/test/exit_test.exs:85` after relinquishing; `core/test/vv_f05_a_test.exs:153` after transferring one item and deleting the other

*Notes:* Departure also drops the leaver's links, plans, marks, and goals (alignment_test.exs:241); not required by this statement.

### REQ-111 · Verified

- **AC-1** A value is an item of kind value, in the member's own words, created by a member and owned by them alone.  
  Evidence: `core/test/alignment_test.exs:18` a value is an ordinary owned item, private by default
- **AC-2** Only a member can create a value.  
  Evidence: `core/test/randomized_test.exs:299` values created by random actors, including a non-member, always have member owners
- **AC-3** Values follow the item rules REQ-101..REQ-110 (owner set, grants, owner changes, history, visibility, aggregates, deletion, export, departure).  
  Evidence: `core/test/alignment_test.exs:27` values obey ownership rules (grant, delete); `core/test/shared_value_test.exs:54` withdraw and delete a shared value; `core/test/randomized_test.exs:294` values take part in every operation and every per-step check
- **AC-4** The system provides no values: a new household, and a newly created vault, contain no items at all, so no values, for any member.  
  Evidence: `core/test/alignment_test.exs:27` a new household has no values; `core/test/vv_f05_a_test.exs:191` a new household has no items; `app/test/vv_f05_a_test.exs:221` a new vault has no items for any member

*Notes:* Interpretation: 'provide no predefined values' means no value exists that a member did not create. The add-value field's placeholder text ('e.g. Time with the kids') is an example in an empty field, not a value, and is not counted. For values REQ-115 adds the joiner's consent to REQ-107; REQ-104 and REQ-109 in the range are superseded (by REQ-107 and REQ-117, now REQ-169).

### REQ-114 · Verified

- **AC-1** Revocation: when a grant on an item or on a value is revoked, the item leaves the member's distribution, and items linked to a lost value count as unlinked.  
  Evidence: `core/test/alignment_test.exs:213` revocation hides the item from links and distribution; `core/test/vv_f05_a_test.exs:319` cases revoke_item, revoke_value
- **AC-2** Relinquishment: when the member relinquishes a jointly owned item or a shared value, it leaves their distribution.  
  Evidence: `core/test/alignment_test.exs:228` relinquishing a shared item removes it from one's distribution; `core/test/vv_f05_a_test.exs:319` cases relinquish_item, relinquish_value
- **AC-3** Deletion: when the owner deletes an item or a value the member could see, it leaves the member's distribution.  
  Evidence: `core/test/vv_f05_a_test.exs:319` cases delete_item, delete_value
- **AC-4** Departure: a member who leaves has an empty distribution and no links.  
  Evidence: `core/test/vv_f05_a_test.exs:319` case departure; `core/test/alignment_test.exs:241` leaving drops the leaver's links
- **AC-5** Silently (interpretation): after any of the four, everything the core returns to the member (distribution, links, export, visible items, pending requests, deletion records, and the answers to link and unlink) is exactly what it would return had they never had that item or link; and after another member revokes or deletes, the member's pages (household pages, their own item and value pages, the lost item's page) are identical, apart from form tokens, to before it was shared.  
  Evidence: `core/test/vv_f05_a_test.exs:319` seven causes compared with a counterfactual household; `app/test/vv_f05_a_test.exs:168` pages after revocation and deletion equal pages before sharing
- **AC-6** Link records reveal nothing (interpretation): no link to an item or value the member can no longer see appears in, or changes, anything the member is shown or given (their link list, the distribution, the export, a value's page, or how link and unlink answer).  
  Evidence: `core/test/alignment_test.exs:213` the hidden link is not listed; `core/test/vv_f05_a_test.exs:319` link-derived results equal the counterfactual; `app/test/vv_f05_a_test.exs:168` the member's value page no longer lists the hidden link

*Notes:* Interpretations, stated plainly: 'silently' = leaves no trace in anything the member sees, which makes the App. A 'untestable as worded' gap observable. In the interface only revocation and deletion by another member are compared page by page; relinquishing and leaving are the member's own acts, whose outcome message is about the act, not a notice of removal. 'Link records shall not reveal anything' = through anything the system shows or returns. Not decided by any test: by design (alignment.ex:14-16) a hidden link stays in the member's own encrypted record and reappears if sight is regained. Whether that stored copy 'reveals' anything is the ruling App. A asks for; this Verified depends on the interpretation above being accepted (human gate requested).

### REQ-115 · Verified

- **AC-1** A proposal adding a member to a value is not applied without that member's own consent, even when every current owner has consented.  
  Evidence: `core/test/shared_value_test.exs:15` a sole owner cannot make someone a co-owner of a value unilaterally; `core/test/randomized_test.exs:350` every joiner of a value consented
- **AC-2** Nor is it applied without every current owner's consent: the joiner can't consent before then.  
  Evidence: `core/test/shared_value_test.exs:25` a prospective member sees the proposal only after every current owner has consented; `core/test/randomized_test.exs:343` every owner change consented by every owner
- **AC-3** The member being added sees the proposal, with the value's attributes, only once every current owner has consented.  
  Evidence: `core/test/shared_value_test.exs:20` the joiner sees the label; `core/test/shared_value_test.exs:25` nothing before, the value after; `app/test/vault_test.exs:117` a prospective joiner can open the value only after every owner consents
- **AC-4** They may then consent, and become an owner.  
  Evidence: `core/test/shared_value_test.exs:15` owners become [:a, :b]; `core/test/shared_value_test.exs:25` owners become [:a, :b, :c]
- **AC-5** Or ignore it: without their consent they are not an owner and the value is unchanged.  
  Evidence: `core/test/shared_value_test.exs:15` owners stay [:a] and the value is not visible to :b until :b consents
- **AC-6** For items that are not values, current owners' consent suffices (REQ-107 unchanged).  
  Evidence: `core/test/shared_value_test.exs:46` ordinary items keep REQ-107; `core/test/household_test.exs:97` an owner added to an ordinary item without their consent

*Notes:* 'Ignore' has no deadline or effect to observe other than nothing happening; AC-5 is that.

### REQ-116 · Verified

- **AC-1** Each participant of a shared value, its creator or a member who joined, can withdraw without anyone else's consent while another participant remains.  
  Evidence: `core/test/shared_value_test.exs:54` the creator withdraws alone; `core/test/vv_f05_a_test.exs:169` each of three participants withdraws alone, then each of the remaining two
- **AC-2** The last participant can delete the value alone.  
  Evidence: `core/test/shared_value_test.exs:54` the last may delete; `core/test/vv_f05_a_test.exs:169` whoever is last deletes

*Notes:* Interpretation: 'participant' = an owner of the value (joined under REQ-115); 'withdraw' = relinquish (REQ-107). A grantee of a value is not a participant: no function lets a grantee drop their own grant, and the statement is not read as requiring one. That the last participant can't withdraw is REQ-101/107, not this statement.

### REQ-118 · Verified

- **AC-1** No member's private key or personal key appears anywhere in the bytes of the stored file.  
  Evidence: `app/test/crypto_properties_test.exs:71` no private key or personal key appears in the stored file
- **AC-2** Each member's private key material is stored only inside their secret box, which opens under PBKDF2-HMAC-SHA256 of their passphrase with their salt and the vault's iteration count, and under no other derivation; the derivation matches the RFC 7914 PBKDF2-HMAC-SHA256 known answers.  
  Evidence: `app/test/crypto_properties_test.exs:52` each member's secret on disk opens under PBKDF2-HMAC-SHA256 of their passphrase, and only that; `app/test/crypto_properties_test.exs:44` derive_key is PBKDF2-HMAC-SHA256 (RFC 7914 known answers)
- **AC-3** A vault made for use (setup, or create without the test-only flag) uses at least 600,000 iterations, and deriving or creating with fewer is refused unless the explicit test-only flag is set.  
  Evidence: `app/test/vault_test.exs:84` REQ-118: the default vault uses at least 600,000 PBKDF2 iterations; `app/test/crypto_test.exs:45` key derivation refuses fewer than 600,000 iterations unless explicitly unsafe; `app/test/tasks_test.exs:11` setup creates a vault each member can unlock, re-asking on a mismatch or a short passphrase
- **AC-4** Each member's salt is 16 random bytes, different from every other member's and every other vault's.  
  Evidence: `app/test/crypto_properties_test.exs:65` every member has a 16-byte salt, different from every other member's and vault's
- **AC-5** A wrong passphrase fails authentication: nothing is unlocked and no session is created (401 at the interface).  
  Evidence: `app/test/vault_test.exs:41` REQ-118: a wrong passphrase or unknown member fails and reveals nothing; `app/test/web_test.exs:82` a wrong passphrase is refused
- **AC-6** Interpretation of 'reveal nothing': every failed unlock (a wrong, empty, near-miss, or another member's passphrase, or a name that is not a member) gets the identical response (status, headers, cookie names, and page, apart from the random per-page tokens) and the identical log line, and the core returns the same single error for all of them.  
  Evidence: `app/test/vv_f05_b_test.exs:150` a wrong passphrase reveals nothing: every failure, for a member or not, looks the same; `app/test/vault_test.exs:41` REQ-118: a wrong passphrase or unknown member fails and reveals nothing

*Notes:* AC-6 is an interpretation: 'reveal nothing' cannot be tested in general, so it is taken as 'no failure can be told from another by what the app returns or logs'. Not tested: response timing. An unknown name skips PBKDF2 and is answered faster, so timing can tell a member's name from a non-member's; the unlock page lists members' names anyway, so this reveals nothing new, but it is recorded for GATE-016. Also for GATE-016 (from VV-001): the iteration count and the test-only flag are read from the plaintext file at unlock.

### REQ-119 · Verified

- **AC-1** Item content (every attribute) is stored only encrypted: no attribute value appears in the bytes of the stored file.  
  Evidence: `app/test/vault_test.exs:144` REQ-122: no attribute, label, link, or ledger detail appears in plaintext in the stored file; `app/test/crypto_properties_test.exs:100` a deletion record, an amount, a date, and a frequency are not in the file in plaintext; `app/test/vv_f05_b_test.exs:198` REQ-122: kinds, account and debt types, every kind of history entry, and plan names stay out of the file
- **AC-2** Each item has its own key, and no item's key opens another item's content.  
  Evidence: `app/test/crypto_properties_test.exs:83` REQ-119: each item has its own key, and one item's key can't open another's content
- **AC-3** The item key is sealed to exactly the item's current owners and grantees: a grant adds a sealed key; revoking, relinquishing, being removed from the owners by agreement, or leaving the household removes it.  
  Evidence: `app/test/vault_test.exs:91` REQ-119: only readers can decrypt an item; a grant adds a reader and revocation removes one; `app/test/vv_f05_b_test.exs:178` REQ-119: an owner who relinquishes, or is removed by agreement, loses the item key; `app/test/vault_test.exs:196` departure removes the leaver's keys and personal record
- **AC-4** A prospective joiner of a value gets the item key once every current owner has consented, not before, and loses it if the proposal is withdrawn.  
  Evidence: `app/test/vault_test.exs:117` REQ-119/120 with REQ-115: a prospective joiner can read a value only after every owner consents; `app/test/vault_test.exs:183` REQ-125: withdrawing a value invitation removes the access the joiner was given in advance
- **AC-5** No other member can open the item key or content from the stored file with their own secrets, including one written into the file's reader lists by editing it.  
  Evidence: `app/test/vault_test.exs:91` REQ-119: only readers can decrypt an item; a grant adds a reader and revocation removes one; `app/test/tamper_test.exs:35` an honest owner's later save does not seal the item key to them; `app/test/vv_f05_b_test.exs:178` REQ-119: an owner who relinquishes, or is removed by agreement, loses the item key

*Notes:* The statement cites only REQ-115 (values) for prospective joiners; shared plans (REQ-148) are also sealed to joiners, which is asserted under REQ-170 AC-5.

### REQ-121 · Verified

- **AC-1** A member's links do not appear in the stored file in plaintext.  
  Evidence: `app/test/crypto_properties_test.exs:126` another member's secrets can't open a member's personal record (links and deletions); `app/test/vault_test.exs:144` REQ-122: no attribute, label, link, or ledger detail appears in plaintext in the stored file
- **AC-2** A member's deletion records do not appear in the stored file in plaintext.  
  Evidence: `app/test/crypto_properties_test.exs:100` a deletion record, an amount, a date, and a frequency are not in the file in plaintext
- **AC-3** Links and deletion records are encrypted under that member's personal key, which is stored only inside their passphrase-protected secret; no other member's secrets open the record.  
  Evidence: `app/test/crypto_properties_test.exs:126` another member's secrets can't open a member's personal record (links and deletions); `app/test/crypto_properties_test.exs:71` no private key or personal key appears in the stored file; `app/test/crypto_properties_test.exs:52` each member's secret on disk opens under PBKDF2-HMAC-SHA256 of their passphrase, and only that; `app/test/vault_test.exs:133` REQ-121: links and deletion records are private to their member

*Notes:* No new test was needed; all criteria were asserted by WI-055 and earlier tests.

### REQ-122 · Verified

- **AC-1** No item attribute appears in the stored file in plaintext: notes, amounts, units, dates, frequencies, kinds, account and debt types, and the names of accounts, debts, and shared plans.  
  Evidence: `app/test/vault_test.exs:144` REQ-122: no attribute, label, link, or ledger detail appears in plaintext in the stored file; `app/test/crypto_properties_test.exs:100` a deletion record, an amount, a date, and a frequency are not in the file in plaintext; `app/test/readings_crypto_test.exs:171` readings are not in the file in plaintext; `app/test/vv_f05_b_test.exs:198` REQ-122: kinds, account and debt types, every kind of history entry, and plan names stay out of the file
- **AC-2** No value label appears in the stored file in plaintext.  
  Evidence: `app/test/vault_test.exs:144` REQ-122: no attribute, label, link, or ledger detail appears in plaintext in the stored file; `app/test/vv_f05_b_test.exs:198` REQ-122: kinds, account and debt types, every kind of history entry, and plan names stay out of the file
- **AC-3** No link (its item and value together) appears in the stored file in plaintext.  
  Evidence: `app/test/crypto_properties_test.exs:126` another member's secrets can't open a member's personal record (links and deletions)
- **AC-4** No ledger entry detail appears in the stored file in plaintext, for every kind of entry (created, granted, grant revoked, owners changed, owner relinquished, grantee departed, reading added).  
  Evidence: `app/test/vault_test.exs:144` REQ-122: no attribute, label, link, or ledger detail appears in plaintext in the stored file; `app/test/vv_f05_b_test.exs:198` REQ-122: kinds, account and debt types, every kind of history entry, and plan names stay out of the file
- **AC-5** No deletion record appears in the stored file in plaintext.  
  Evidence: `app/test/crypto_properties_test.exs:100` a deletion record, an amount, a date, and a frequency are not in the file in plaintext

*Notes:* Plaintext structure that the statement does not cover stays in the file by design (ASM-020): item ids, owner and grantee lists, proposals, and ledger and reading sequence numbers. Tests search the file's bytes for markers and for the external term encoding of numbers and frequencies.

### REQ-123 · Verified

- **AC-1** The server binds 127.0.0.1 only.  
  Evidence: `app/test/web_test.exs:56` binds only the loopback address; `app/test/end_to_end_test.exs:118` a member uses the real server over loopback, and everything survives a restart
- **AC-2** A request, GET or POST, whose Host is not the loopback address with the server's port is refused (421) before anything is processed; a POST so refused creates no session.  
  Evidence: `app/test/web_test.exs:62` rejects a foreign Host header (DNS rebinding); `app/test/vv_f05_b_test.exs:430` a request naming any host but the loopback address and port is refused, a POST included; `app/test/end_to_end_test.exs:118` a member uses the real server over loopback, and everything survives a restart
- **AC-3** Every state-changing request needs a valid CSRF token: each of the 35 POST routes the router declares, sent from an unlocked session with a one-time form token but with the CSRF token missing, from another session, or altered, is refused (403, 'That wasn't saved'), the file is unchanged, and the session stays as it was. Requests other than POST change nothing.  
  Evidence: `app/test/vv_f05_b_test.exs:323` every state-changing request needs a valid CSRF token: each POST route refuses without one; `app/test/vv_f05_b_test.exs:388` no request other than a POST changes the household: every GET route leaves the file as it was; `app/test/web_test.exs:72` rejects a state-changing request without a CSRF token; `app/test/def035_test.exs:54` Ana's old tab, after Ana locks and Ben unlocks in the same browser, says nothing was saved
- **AC-4** Logging out (Lock) discards the session's unlocked keys.  
  Evidence: `app/test/web_test.exs:87` logout discards the unlocked session
- **AC-5** The idle limit is 15 minutes: a session idle for 15 minutes still holds its keys; once idle for longer, its keys are discarded without any request, leaving a marker with only its time, within the sweep interval (5 seconds) of the server as started.  
  Evidence: `app/test/vv_f05_b_test.exs:455` the idle limit is 15 minutes: a session is kept at exactly 15 minutes and discarded after; `app/test/vv_f05_b_test.exs:473` as the server starts it, the sweep discards an idle session's keys within 5 seconds; `app/test/wi052_test.exs:78` DEF-039: the sweep leaves an idle session with nothing but a marker; `app/test/wi052_test.exs:111` DEF-039: the sweep runs by itself, with no request

*Notes:* Interpretations: (1) 'state-changing request' is every POST: the router declares only GET and POST routes, and every GET route leaves the stored file unchanged (asserted). Observation, not a finding: any request other than a bring-in POST drops a checked bring-in file waiting in memory (DEF-044, by design); with SameSite=Strict cookies a cross-site request carries no session, so it cannot do this. (2) 'the loopback address' is taken as 127.0.0.1; the code also accepts localhost with the port, which names it, and (by reading the code) refuses other loopback addresses such as 127.0.0.2, which the statement does not forbid. (3) 'after 15 minutes idle' is met within the 5-second sweep interval, which closes VV-001 F-02 as WI-052 intended. The route list in AC-3 is read from the router's source, so a new POST route makes the test fail until it is added.

### REQ-124 · Verified

- **AC-1** Interpretation of 'no outbound network connections': during a member's whole visit through the interface (unlock and a failed unlock, every kind of page, changes of each main kind, export, bring-in, lock, and a second member's visit), no process in the running system calls a TCP, UDP, SCTP, or TLS connect or a host-name lookup; and neither the app nor its dependencies contain an HTTP client or connect call.  
  Evidence: `app/test/vv_f05_b_test.exs:618` a member's whole visit opens no outbound connection; `app/test/web_test.exs:115` no HTTP client or outbound-connection code in the app or its dependencies
- **AC-2** Interpretation of 'load no remote resources': every kind of page the interface serves (31 responses, including error, refusal, confirmation, preview, and export pages) carries a Content-Security-Policy whose default-src is 'none' and whose every source is 'none', 'self', or 'unsafe-inline'; and no page refers to a remote address (absolute or protocol-relative URL, CSS url() or @import).  
  Evidence: `app/test/vv_f05_b_test.exs:684` every kind of page forbids remote loads and refers to nothing remote; `app/test/web_test.exs:107` every response forbids remote loads, and pages contain no remote URLs

*Notes:* Both criteria are interpretations; a universal 'makes no connection' cannot be shown by tests. Limits: AC-1 traces the functions named, in the test VM, over the paths the visit exercises, with requests made in-process (Plug.Test), not through the Bandit listener, and no operating-system capture was made (VV-RUN-001 observed none in one snapshot). A connection opened another way (a NIF, a port program) would not be seen. AC-2 relies on browsers enforcing the policy; no browser was run. The 421 refusal is sent before the security headers and has no policy, but its body is plain text with nothing to load.

### REQ-125 · Verified

- **AC-1** While a proposal is pending, the member who made it can withdraw it.  
  Evidence: `core/test/exit_test.exs:131` the proposer withdraws; `core/test/vv_f05_a_test.exs:447` in every reached state the proposer can withdraw each pending proposal
- **AC-2** While it is pending, any current owner of its item, including an owner added after it was made, can withdraw it; nobody else can.  
  Evidence: `core/test/exit_test.exs:139` any current owner may withdraw someone else's proposal; `core/test/exit_test.exs:146` non-owners, grantees, and prospective joiners cannot withdraw; `core/test/randomized_test.exs:226` owners succeed and non-owners are refused; `core/test/vv_f05_a_test.exs:447` every current owner can withdraw
- **AC-3** Withdrawing removes that proposal only and changes nothing else.  
  Evidence: `core/test/exit_test.exs:131` the proposal is gone and nothing changed; `core/test/randomized_test.exs:227` only that proposal goes; items and ledger untouched; `core/test/vv_f05_a_test.exs:447` only that proposal goes
- **AC-4** Under the recorded interpretation ('the proposer counts while still an owner'): in every reachable state, the proposer of each pending proposal is a current owner of its item, so the proposer can always withdraw it while it is pending.  
  Evidence: `core/test/exit_test.exs:163` a proposer who agrees to leave the owners loses their pending proposals; `core/test/exit_test.exs:186` relinquishing drops the relinquisher's proposals; `core/test/vv_f05_a_test.exs:447` 400 seeded walks; checked after every step; at least 20 lapses exercised

*Notes:* Verified against its recorded interpretation, as in App. A. VV-001 D2 (a proposer removed by an agreed owner change kept a proposal they could not withdraw) was fixed by DEF-040 (WI-053); AC-4's random walk checks every path, not only the two tested before.

### REQ-128 · Verified

- **AC-1** Only items visible to the member are counted.  
  Evidence: `core/test/alignment_test.exs:200` only the requester's visible items and own links count; `core/test/randomized_test.exs:510` distribution recomputed from the ledger replay
- **AC-2** Only the member's own links are used.  
  Evidence: `core/test/alignment_test.exs:200` :b's distribution ignores :a's link; `core/test/alignment_test.exs:56` two members link the same item differently
- **AC-3** There is one bucket per value visible to the member plus an explicit unlinked remainder, and nothing else.  
  Evidence: `core/test/alignment_test.exs:82` per-value buckets plus an unlinked remainder, nothing else
- **AC-4** Each bucket reports the number of items counted.  
  Evidence: `core/test/alignment_test.exs:82` count; `core/test/alignment_test.exs:89` count: 6
- **AC-5** Each bucket reports per-month sums of money in and of money out over recurring items, each item converted to a per-month amount and rounded to the smallest unit before summing.  
  Evidence: `core/test/alignment_test.exs:89` converted one by one, then summed; in and out apart; `core/test/alignment_test.exs:121` rounds half away from zero, symmetrically
- **AC-6** The conversion is: every N weeks x 52 / (12 N); every N months / N; every N years / (12 N); irregular (a yearly total) / 12.  
  Evidence: `core/test/alignment_test.exs:130` intervals and irregular yearly totals convert per item; `core/test/randomized_test.exs:510` independent factors per stored frequency
- **AC-7** Each bucket reports, separately, the sums of money in and of money out over one-off items.  
  Evidence: `core/test/alignment_test.exs:89` one_off in and out
- **AC-8** An item with no recorded or an unrecognized frequency counts as one-off.  
  Evidence: `core/test/alignment_test.exs:82` no frequency means one-off; `core/test/alignment_test.exs:152` malformed intervals count as one-off; `core/test/alignment_test.exs:184` an unknown frequency counts as one-off
- **AC-9** The distribution contains no score, rank, threshold, or evaluative label: its buckets hold only count, per-month in/out, and one-off in/out, and the page that shows it has no evaluative words.  
  Evidence: `core/test/alignment_test.exs:82` exact result shape; `app/test/frequency_test.exs:134` totals shown with nothing evaluative

*Notes:* Interpretation for AC-9: 'no evaluative content' = the result has no field beyond the counts and sums, and the shown totals contain none of the listed evaluative words. The rounding mode (half away from zero) is not stated by the Requirement (App. A spec note); the tests fix it.

### REQ-129 · Verified

- **AC-1** Adding an item offers exactly nine choices of how often: one-off, every week, every two weeks, every month, every two months, every three months, twice a year, every year, and irregular, the last saying the amount is the total for a year.  
  Evidence: `app/test/vv_f05_b_test.exs:739` adding an item offers exactly the nine choices, with none chosen; `app/test/frequency_test.exs:180` CP-012: every preset is offered, stored, shown, converted, and exported
- **AC-2** The System does not choose: no choice is preselected, and an item sent with no choice or an unknown one is not saved and the member is told to choose.  
  Evidence: `app/test/vv_f05_b_test.exs:739` adding an item offers exactly the nine choices, with none chosen; `app/test/frequency_test.exs:67` the form offers no default: nothing chosen or an unknown choice saves nothing, and says why
- **AC-3** For irregular, the amount entered is kept as the total for a year (counted as a twelfth of it a month).  
  Evidence: `app/test/frequency_test.exs:180` CP-012: every preset is offered, stored, shown, converted, and exported; `core/test/alignment_test.exs:130` REQ-128: intervals and irregular yearly totals convert per item; legacy values match their intervals
- **AC-4** Each choice is stored as one-off, irregular, or an interval {every, N, week|month|year}, exactly as chosen.  
  Evidence: `app/test/vv_f05_b_test.exs:751` each of the nine is stored as chosen and shown beside the amount on home, its page, export, and set-asides; `core/test/alignment_test.exs:167` the presets the interface offers are all valid, in order
- **AC-5** The choice is stored with the item's other protected attributes (encrypted, not in the file in plaintext).  
  Evidence: `app/test/crypto_properties_test.exs:100` a deletion record, an amount, a date, and a frequency are not in the file in plaintext; `app/test/vv_f05_b_test.exs:198` REQ-122: kinds, account and debt types, every kind of history entry, and plan names stay out of the file
- **AC-6** Wherever the item's amount is shown (the home list, the item's page, the export page, and the set-aside list), how often it happens is shown beside it. A row for one dated occurrence (Coming up, the next 60 days) shows that occurrence, not the item's amount, and need not (REV-070).  
  Evidence: `app/test/frequency_test.exs:100` the frequency is stored and shown wherever the amount is; `app/test/cash_flow_web_test.exs:135` REQ-139/140: the 60-day page names the days below zero and the set-asides
- **AC-7** Items stored with the earlier frequencies (weekly, biweekly, monthly, yearly) read, count, and show as the same intervals.  
  Evidence: `core/test/vv_f05_b_test.exs:220` REQ-129: items stored with the earlier frequencies read as the same intervals; `app/test/vv_f05_b_test.exs:791` items stored with the earlier frequencies read and show as the same intervals; `app/test/frequency_test.exs:219` an item stored with a legacy frequency still reads and converts the same; `core/test/alignment_test.exs:130` REQ-128: intervals and irregular yearly totals convert per item; legacy values match their intervals

*Notes:* DEFECT (AC-6, literal reading): the dated rows of Coming up (home) and of the next sixty days show an item's amount without how often it happens (web/html.ex flow_rows: title and format_amount only). Reproduce: unlock; add a checking account; add an item 'Rent', 1,450, money out, every month, date 2026-10-01 (with today fixed at 2026-09-27); on home and on /next-60-days the Rent row reads 'Rent −$1,450.00' with no 'a month'. The home list, item page, export page, and set-aside list do show it (asserted in app/test/vv_f05_b_test.exs:746 and frequency_test.exs:100). The failing test was removed. Whether one dated occurrence in a day-by-day schedule counts as 'the item's amount' is a question of meaning for the Requirement's owner: if it does not, AC-6 narrows to the four places tested and the result would be Verified. Not changed: code or Requirement.

### REQ-131 · Verified

- **AC-1** Any owner of an account or debt, a joint owner included, adds a reading without anyone else's consent: it applies at once and creates no proposal.  
  Evidence: `core/test/balances_test.exs:38` either joint owner adds a reading without asking the other; `core/test/vv_f05_b_test.exs:212` a joint owner's reading needs nobody else's consent: it applies at once, with no proposal; `app/test/readings_crypto_test.exs:111` a joint owner can add a reading and the other owner can read every reading
- **AC-2** Nobody else can add one: a member it is shared with is refused as not an owner, and anyone who cannot see it is refused as if it did not exist, in the core and at the interface.  
  Evidence: `core/test/balances_test.exs:49` someone who can see it but doesn't own it, or can't see it, can't add one; `app/test/balances_web_test.exs:182` shared with someone: they see the latest only, and can't update it; `core/test/randomized_test.exs:20` REQ-101..114 and REQ-125 hold after every operation of 2000 seeded sequences
- **AC-3** An account's reading is its balance; a debt's is the amount owed (not negative), the interest rate, and the minimum payment; anything else is refused.  
  Evidence: `core/test/balances_test.exs:57` readings are validated by kind; `app/test/balances_web_test.exs:73` adding an account, then its balance, from its own page; `app/test/balances_web_test.exs:131` a debt: what's owed, the rate, the minimum, and a month's interest as a fact
- **AC-4** Every reading has the date it is as of; a reading with no date or an invalid one is refused.  
  Evidence: `core/test/vv_f05_b_test.exs:201` a reading needs the date it is as of; `core/test/balances_test.exs:57` readings are validated by kind
- **AC-5** Readings are append-only: after any operation, an item's earlier readings are unchanged and numbered without gaps.  
  Evidence: `core/test/randomized_test.exs:20` REQ-101..114 and REQ-125 hold after every operation of 2000 seeded sequences
- **AC-6** Each reading is recorded in the item's history.  
  Evidence: `core/test/balances_test.exs:38` either joint owner adds a reading without asking the other; `core/test/randomized_test.exs:20` REQ-101..114 and REQ-125 hold after every operation of 2000 seeded sequences

*Notes:* The randomized test's per-step readings checks (readings_checks!) assert AC-2, AC-5, and AC-6 after every operation. Deleting the item removes its readings (REQ-108), which is not a change to a reading.

### REQ-132 · Verified

- **AC-1** A member who can read an account or debt (an owner or a grantee) can read its latest reading.  
  Evidence: `core/test/balances_test.exs:84` owners read all; someone it's shared with reads only the latest; others none; `app/test/readings_crypto_test.exs:70` owners hold every reading's key; someone it's shared with only the latest; nobody else any; `app/test/balances_web_test.exs:182` shared with someone: they see the latest only, and can't update it
- **AC-2** Its owners can read all of its readings; a reader who is not an owner cannot read the earlier ones.  
  Evidence: `core/test/balances_test.exs:84` owners read all; someone it's shared with reads only the latest; others none; `app/test/readings_crypto_test.exs:70` owners hold every reading's key; someone it's shared with only the latest; nobody else any; `app/test/readings_crypto_test.exs:111` a joint owner can add a reading and the other owner can read every reading
- **AC-3** Nobody else can read any reading, through the core or from the stored file.  
  Evidence: `core/test/balances_test.exs:84` owners read all; someone it's shared with reads only the latest; others none; `app/test/readings_crypto_test.exs:70` owners hold every reading's key; someone it's shared with only the latest; nobody else any; `core/test/randomized_test.exs:20` REQ-101..114 and REQ-125 hold after every operation of 2000 seeded sequences

*Notes:* REQ-102, cited by the statement, is superseded by REQ-167; for an account or debt the readers are its owners and grantees (no prospective joiners, which apply only to values and shared plans). No new test was needed.

### REQ-133 · Verified

- **AC-1** Each reading is encrypted with its own key.  
  Evidence: `app/test/crypto_properties_test.exs:164` each reading has its own key
- **AC-2** When written, a reading's key is sealed only to the members REQ-132 allows: the latest to every owner and grantee, earlier ones to owners only.  
  Evidence: `app/test/readings_crypto_test.exs:70` owners hold every reading's key; someone it's shared with only the latest; nobody else any; `app/test/readings_crypto_test.exs:111` a joint owner can add a reading and the other owner can read every reading
- **AC-3** A member who gains access is sealed the keys they may now use: a new grantee the latest, a new owner every earlier reading.  
  Evidence: `app/test/readings_crypto_test.exs:70` owners hold every reading's key; someone it's shared with only the latest; nobody else any; `app/test/crypto_properties_test.exs:170` a member who becomes an owner gets every earlier reading's key; one who relinquishes loses them
- **AC-4** A member who loses access has their keys removed: on revocation, relinquishing, removal from the owners by agreement, leaving the household, and, for a grantee, a reading ceasing to be the latest.  
  Evidence: `app/test/readings_crypto_test.exs:123` someone who stops being able to see it loses their keys, and never gets later readings; `app/test/crypto_properties_test.exs:170` a member who becomes an owner gets every earlier reading's key; one who relinquishes loses them; `app/test/vv_f05_b_test.exs:828` an owner removed by agreement loses every reading key and gets none for later readings; `app/test/vv_f05_b_test.exs:821` a grantee who leaves the household loses their reading key; `app/test/readings_crypto_test.exs:93` when a newer reading arrives, the grantee's key to the old latest is removed
- **AC-5** A member who lost access is never given a key to a reading written afterwards.  
  Evidence: `app/test/readings_crypto_test.exs:123` someone who stops being able to see it loses their keys, and never gets later readings; `app/test/vv_f05_b_test.exs:828` an owner removed by agreement loses every reading key and gets none for later readings
- **AC-6** A reader written into the file without the app adding them is never given a reading key.  
  Evidence: `app/test/readings_crypto_test.exs:147` a reader written into the file by editing it is never sealed a reading, and it's reported

*Notes:* Removal means the sealed key is absent from the file the app writes next; a copy of an older file still holds what it held (readings_crypto_test.exs:123 notes this).

### REQ-134 · Verified

- **AC-1** Accounts and debts, whether the member owns them or they are shared with them, and whatever readings they have, are not counted in any bucket of the distribution (count, per-month, or one-off).  
  Evidence: `core/test/balances_test.exs:113` a joint account is left out; `core/test/randomized_test.exs:510` an account-or-debt slot left out in the independent recomputation; `core/test/vv_f05_a_test.exs:461` an owned account, an owned debt, and a shared debt, all with readings, are left out
- **AC-2** No account or debt can be linked to a value.  
  Evidence: `core/test/balances_test.exs:113` an account can't be linked; `core/test/vv_f05_a_test.exs:461` an account, an owned debt, and a shared debt can't be linked

*Notes:* App. A gap (linking a debt never attempted) is closed by vv_f05_a_test.exs:461. The same test also shows an account or debt can't be the value end of a link. Bringing in a file links through the same function (import.ex:770).

### REQ-136 · Verified

- **AC-1** Adding an item accepts one date on which it happens, stored on the item (attrs.on).  
  Evidence: `app/test/cash_flow_web_test.exs:69` REQ-136: a date is optional, checked, stored, and shown as the next date; irregular items keep none
- **AC-2** The add-item form offers exactly one date field, and it is optional: an item can be added without a date.  
  Evidence: `app/test/vv_f05_c_test.exs:116` REQ-136: the add-item form offers exactly one date, and it is optional; `app/test/cash_flow_web_test.exs:69` REQ-136: a date is optional, checked, stored, and shown as the next date; irregular items keep none
- **AC-3** A recurring item with a date happens on that date and on its schedule from it, never before it.  
  Evidence: `core/test/schedule_test.exs:18` every 2 weeks is every 14 days from the date, never before it; `core/test/schedule_test.exs:13` monthly on the 31st lands on each month's last day, including a leap February
- **AC-4** A one-off with a date happens on that date only.  
  Evidence: `core/test/schedule_test.exs:23` twice a year, yearly, one-off, irregular, and no date
- **AC-5** An irregular item has no dates: none is stored even if one is entered, and it has no occurrences.  
  Evidence: `app/test/cash_flow_web_test.exs:69` REQ-136: a date is optional, checked, stored, and shown as the next date; irregular items keep none; `core/test/schedule_test.exs:23` twice a year, yearly, one-off, irregular, and no date
- **AC-6** The date is kept in the item's protected (encrypted) attributes and does not appear in plaintext in the stored file.  
  Evidence: `app/test/crypto_properties_test.exs:100` a deletion record, an amount, a date, and a frequency are not in the file in plaintext
- **AC-7** An item without a date is still added, listed, and counted at its per-month amount in totals and the twelve-month projection; it simply has no dates.  
  Evidence: `app/test/cash_flow_web_test.exs:69` REQ-136: a date is optional, checked, stored, and shown as the next date; irregular items keep none; `core/test/plans_projection_test.exs:49` months start after this one; cash runs from the account balances; one-offs land in their month

*Notes:* 'Keep working as before' is read as AC-7: an undated item is accepted and counted exactly as items were before dates existed (the undated health premium counts 400 a month in the projection). An invalid date is refused (cash_flow_web_test.exs:69); the statement does not require that, so it is not a criterion.

### REQ-137 · Verified

- **AC-1** Every N weeks: the dates are the item's date plus 7N, 14N, ... days (N = 1, 2, 3 tested).  
  Evidence: `core/test/schedule_test.exs:18` every 2 weeks is every 14 days from the date, never before it; `core/test/schedule_test.exs:43` legacy frequency values schedule like their intervals; `core/test/vv_f05_c_test.exs:27` every 3 weeks is every 21 days from the date
- **AC-2** Every N months: the same day of the month every N months (N = 1, 2, 3, 6 tested).  
  Evidence: `core/test/schedule_test.exs:13` monthly on the 31st lands on each month's last day, including a leap February; `core/test/schedule_test.exs:23` twice a year, yearly, one-off, irregular, and no date; `core/test/vv_f05_c_test.exs:35` every 2 months from the 31st: the same day, or the month's last day when shorter; `core/test/vv_f05_c_test.exs:52` every 3 months from the 30th keeps the 30th, and February's last day
- **AC-3** Every N years: the same day of the month every N years (N = 1, 2 tested).  
  Evidence: `core/test/schedule_test.exs:23` twice a year, yearly, one-off, irregular, and no date; `core/test/vv_f05_c_test.exs:60` every 2 years from February 29
- **AC-4** When the month is shorter than the item's day, the date is that month's last day, and later dates return to the item's own day.  
  Evidence: `core/test/schedule_test.exs:13` monthly on the 31st lands on each month's last day, including a leap February; `core/test/vv_f05_c_test.exs:35` every 2 months from the 31st: the same day, or the month's last day when shorter; `core/test/vv_f05_c_test.exs:60` every 2 years from February 29

*Notes:* N is general in the statement; the interface offers N = 1, 2 weeks, 1, 2, 3, 6 months, and 1 year. Tests now cover an N other than 1 for each unit.

### REQ-140 · Verified

- **AC-1** An owned money-out item every two months is covered, at amount / 2 a month.  
  Evidence: `core/test/vv_f05_c_test.exs:70` every 2 months, every 3 months, and yearly are covered at their monthly amounts; weekly, every 2 weeks, monthly, and one-off are not; `app/test/vv_f05_c_test.exs:128` REQ-140: every 2 months, every 3 months, and yearly money out are set aside for; more frequent and one-off money out aren't
- **AC-2** An owned money-out item every three months is covered, at amount / 3 a month.  
  Evidence: `core/test/vv_f05_c_test.exs:70` every 2 months, every 3 months, and yearly are covered at their monthly amounts; weekly, every 2 weeks, monthly, and one-off are not; `app/test/vv_f05_c_test.exs:128` REQ-140: every 2 months, every 3 months, and yearly money out are set aside for; more frequent and one-off money out aren't
- **AC-3** An owned money-out item twice a year is covered, at amount / 6 a month.  
  Evidence: `core/test/schedule_test.exs:126` REQ-140 set-asides for money out less often than monthly; `app/test/cash_flow_web_test.exs:135` REQ-139/140: the 60-day page names the days below zero and the set-asides
- **AC-4** An owned yearly money-out item is covered, at amount / 12 a month.  
  Evidence: `core/test/vv_f05_c_test.exs:70` every 2 months, every 3 months, and yearly are covered at their monthly amounts; weekly, every 2 weeks, monthly, and one-off are not; `app/test/vv_f05_c_test.exs:128` REQ-140: every 2 months, every 3 months, and yearly money out are set aside for; more frequent and one-off money out aren't
- **AC-5** An owned irregular money-out item (a yearly total) is covered, at total / 12 a month.  
  Evidence: `core/test/schedule_test.exs:126` REQ-140 set-asides for money out less often than monthly; `app/test/cash_flow_web_test.exs:135` REQ-139/140: the 60-day page names the days below zero and the set-asides
- **AC-6** Money out that happens monthly or more often (weekly, every two weeks, monthly) and one-off money out are not covered.  
  Evidence: `core/test/vv_f05_c_test.exs:70` every 2 months, every 3 months, and yearly are covered at their monthly amounts; weekly, every 2 weeks, monthly, and one-off are not; `app/test/vv_f05_c_test.exs:128` REQ-140: every 2 months, every 3 months, and yearly money out are set aside for; more frequent and one-off money out aren't
- **AC-7** Money in, however often, is not covered.  
  Evidence: `core/test/schedule_test.exs:126` REQ-140 set-asides for money out less often than monthly
- **AC-8** Only items the member owns are covered; an item others only share with them is not.  
  Evidence: `core/test/schedule_test.exs:126` REQ-140 set-asides for money out less often than monthly
- **AC-9** The member sees the total monthly amount, equal to the sum of the covered items' monthly amounts.  
  Evidence: `app/test/cash_flow_web_test.exs:135` REQ-139/140: the 60-day page names the days below zero and the set-asides; `app/test/vv_f05_c_test.exs:128` REQ-140: every 2 months, every 3 months, and yearly money out are set aside for; more frequent and one-off money out aren't
- **AC-10** The member sees which items the amount covers, each by name with its own monthly amount.  
  Evidence: `app/test/cash_flow_web_test.exs:135` REQ-139/140: the 60-day page names the days below zero and the set-asides; `app/test/vv_f05_c_test.exs:128` REQ-140: every 2 months, every 3 months, and yearly money out are set aside for; more frequent and one-off money out aren't

*Notes:* 'Less often than monthly' is read by the statement's own list; one-off items are not in it, so AC-6 excludes them. The code also treats every 5 or more weeks as less often than monthly; the interface does not offer that interval, so it is not a criterion here.

### REQ-142 · Verified

- **AC-1** A member can create a plan with a name; an empty name is refused.  
  Evidence: `app/test/v03_web_test.exs:117` REQ-142/143: a plan compared with things as they are; steps checked; private; `core/test/plans_projection_test.exs:131` steps are checked, removable, and plans are private
- **AC-2** A member can keep several plans, each with any number of steps.  
  Evidence: `app/test/v03_web_test.exs:117` REQ-142/143: a plan compared with things as they are; steps checked; private; `core/test/plans_projection_test.exs:75` a plan: the job stops (taking the marked premium with it), a new cost, and borrowing
- **AC-3** A switch-off step turns off items the member owns from a month; items they don't own, and non-money items, are refused.  
  Evidence: `core/test/plans_projection_test.exs:75` a plan: the job stops (taking the marked premium with it), a new cost, and borrowing; `core/test/plans_projection_test.exs:131` steps are checked, removable, and plans are private
- **AC-4** A planned money-in or money-out step with how often it happens applies from a month; a planned one-off happens once, in that month.  
  Evidence: `core/test/plans_projection_test.exs:75` a plan: the job stops (taking the marked premium with it), a new cost, and borrowing; `core/test/plans_projection_test.exs:113` a planned one-off happens once, in the month it's planned from
- **AC-5** A borrow step takes an amount, a rate, and a monthly payment, from a month.  
  Evidence: `core/test/plans_projection_test.exs:75` a plan: the job stops (taking the marked premium with it), a new cost, and borrowing; `app/test/v03_web_test.exs:117` REQ-142/143: a plan compared with things as they are; steps checked; private
- **AC-6** Steps can be added and removed.  
  Evidence: `core/test/plans_projection_test.exs:131` steps are checked, removable, and plans are private; `app/test/v03_web_test.exs:117` REQ-142/143: a plan compared with things as they are; steps checked; private
- **AC-7** Plans are private: another member can't see, open, or add to them.  
  Evidence: `app/test/v03_web_test.exs:117` REQ-142/143: a plan compared with things as they are; steps checked; private; `core/test/plans_projection_test.exs:131` steps are checked, removable, and plans are private
- **AC-8** Plans never change a real total: the twelve months as things are, the distribution totals, the running balance, set-asides, and how long savings would last are the same with or without a plan.  
  Evidence: `core/test/plans_projection_test.exs:75` a plan: the job stops (taking the marked premium with it), a new cost, and borrowing; `app/test/v03_web_test.exs:117` REQ-142/143: a plan compared with things as they are; steps checked; private; `core/test/vv_f05_c_test.exs:91` a plan with every kind of step leaves the running balance, set-asides, and savings cover as they were

*Notes:* 'Real totals' is read as every figure computed from what is real: home's distribution totals, the running balance (Coming up and 60 days), set-asides, the next twelve months as things are, and savings cover (AC-8).

### REQ-143 · Verified

- **AC-1** For a plan, the member sees the twelve months, each with the figure without the plan and with it, side by side.  
  Evidence: `app/test/v03_web_test.exs:117` REQ-142/143: a plan compared with things as they are; steps checked; private; `app/test/vv_f05_c_test.exs:170` the twelve months side by side, with and without, and the interest on the borrowing stated
- **AC-2** The with-plan figures include interest on planned borrowing, and the page states that interest.  
  Evidence: `core/test/plans_projection_test.exs:75` a plan: the job stops (taking the marked premium with it), a new cost, and borrowing; `app/test/vv_f05_c_test.exs:170` the twelve months side by side, with and without, and the interest on the borrowing stated
- **AC-3** Each place a plan (a member's own plan or a shared plan) is named or listed says, in that entry or its section, that it is a plan. Places enumerated: the plans list, a plan's page, the confirm-delete page for a plan, a plan request's preview, a shared plan's page, home's request lines (to the member asked and to the proposer), the leave checklist, the export page, and the stop-owning and delete confirmations for a shared plan.  
  Evidence: `app/test/vv_f05_c_test.exs:188` the places a plan appears that say it is a plan: plans list, plan page, request, shared plan page, the asked member's home; `app/test/v03_web_test.exs:322` REQ-148: a plan proposed to another member is shared only when they agree; `app/test/ux004_test.exs:216` P3 (REQ-166): deleting a plan is previewed by name and confirmed; going back keeps it; `app/test/wi058_test.exs:19` the proposal line on the owner's home; `app/test/wi058_test.exs:24` the export page, the leave page, and the confirmation to stop owning

*Notes:* DEFECT (AC-3): a shared plan is listed without saying it is a plan on the proposer's home ('Waiting for others: Make “Trip” owned by ana and ben.'), on /leave ('Trip ... Stop owning'), on /export (under 'Items': 'Trip. Owned by ana and you.'), and on the stop-owning confirmation ('Stop owning “Trip”?'). Reproduced over HTTP (see the WI-057 report). Interpretation: 'a plan' includes a shared plan, which REQ-148 makes from one of the member's plans and calls a 'shared plan'; 'every place' is enumerated in AC-3 as each page entry that names or lists a plan. If a human rules that only a member's own (private) plans are meant, every enumerated place for them says it is a plan and AC-3 passes. The flash message after starting a plan ('Started “Trip”. Add its steps below.') does not itself say plan but sits on the plan's page directly above 'A plan, private to you.'; counted as saying it. The saved JSON file is not a page and was not enumerated.

### REQ-144 · Verified

- **AC-1** A member can mark an item they own as depending on an income item they own.  
  Evidence: `app/test/v03_web_test.exs:225` REQ-144: marking what depends on a job; the plan switches it off too; `core/test/plans_projection_test.exs:171` marks: only between items the member owns, on an income, private
- **AC-2** The job must be an income item the member owns; marking against anything else, or items they don't own, is refused.  
  Evidence: `core/test/plans_projection_test.exs:171` marks: only between items the member owns, on an income, private
- **AC-3** A member can remove a mark.  
  Evidence: `app/test/v03_web_test.exs:225` REQ-144: marking what depends on a job; the plan switches it off too; `core/test/plans_projection_test.exs:171` marks: only between items the member owns, on an income, private
- **AC-4** When a plan switches off the income item, the items marked as depending on it switch off too, from the same month.  
  Evidence: `core/test/plans_projection_test.exs:75` a plan: the job stops (taking the marked premium with it), a new cost, and borrowing; `app/test/v03_web_test.exs:225` REQ-144: marking what depends on a job; the plan switches it off too
- **AC-5** Marks are private: another member has none of them and can't make or read them.  
  Evidence: `core/test/plans_projection_test.exs:171` marks: only between items the member owns, on an income, private

*Notes:* No new test was needed.

### REQ-145 · Verified

- **AC-1** On a debt's page, the months to clear it paying only the minimum, and the interest over that time.  
  Evidence: `app/test/v03_web_test.exs:260` REQ-145: the debt's what-if is worked out on its page and stores nothing; `core/test/plans_projection_test.exs:197` months and interest at a payment; an extra amount clears it sooner for less; too little never clears
- **AC-2** The same with an extra monthly amount the member enters.  
  Evidence: `app/test/v03_web_test.exs:260` REQ-145: the debt's what-if is worked out on its page and stores nothing; `app/test/vv_f05_c_test.exs:233` a member it's shared with sees the what-ifs, worked out from the latest reading
- **AC-3** The monthly interest at a different rate the member enters.  
  Evidence: `app/test/v03_web_test.exs:260` REQ-145: the debt's what-if is worked out on its page and stores nothing; `app/test/vv_f05_c_test.exs:233` a member it's shared with sees the what-ifs, worked out from the latest reading
- **AC-4** Every figure is worked out from the debt's latest reading, for owners and for others who can see it.  
  Evidence: `app/test/vv_f05_c_test.exs:233` a member it's shared with sees the what-ifs, worked out from the latest reading; `app/test/vv_f05_c_test.exs:252` for an owner too, the what-ifs are worked out from the latest of several readings
- **AC-5** A member the debt is shared with (not an owner) sees all three.  
  Evidence: `app/test/vv_f05_c_test.exs:233` a member it's shared with sees the what-ifs, worked out from the latest reading
- **AC-6** The results are stated as facts: no judgment words.  
  Evidence: `app/test/vv_f05_c_test.exs:266` no payment order is suggested: a debt's what-if names no other debt and no order to pay in
- **AC-7** Nothing is stored: the vault file is unchanged after working out what-ifs.  
  Evidence: `app/test/v03_web_test.exs:260` REQ-145: the debt's what-if is worked out on its page and stores nothing
- **AC-8** No payment order is suggested: with two debts, neither debt's what-if names the other debt or uses ordering or advice words (first, before, next, priority, avalanche, snowball, should, recommend, instead, highest, lowest, focus, target).  
  Evidence: `app/test/vv_f05_c_test.exs:266` no payment order is suggested: a debt's what-if names no other debt and no order to pay in

*Notes:* 'No payment order is suggested' is made observable as AC-8. It covers the debt's page, which is where the statement places the what-ifs; the /ahead debts list (sorted by name) is outside this statement. The word list is an interpretation and cannot prove the absence of every possible suggestion.

### REQ-146 · Verified

- **AC-1** A member can set, and clear, an emergency fund goal as a number of months of money out; an out-of-range value is refused.  
  Evidence: `app/test/v03_web_test.exs:283` REQ-146/147: how long savings would last, the member's goal, and a set-aside rate; `core/test/plans_projection_test.exs:208` how long savings would cover money out, against the member's own goal
- **AC-2** The member sees how long the savings accounts they can see (their own and ones shared with them) would cover the money out of the items they own; money out of items only shared with them is not counted.  
  Evidence: `core/test/plans_projection_test.exs:208` how long savings would cover money out, against the member's own goal; `core/test/vv_f05_c_test.exs:146` a savings account shared with the member counts; money out they don't own doesn't; `app/test/v03_web_test.exs:283` REQ-146/147: how long savings would last, the member's goal, and a set-aside rate
- **AC-3** With a goal set, the member sees their progress toward it.  
  Evidence: `app/test/v03_web_test.exs:283` REQ-146/147: how long savings would last, the member's goal, and a set-aside rate
- **AC-4** The goal is private: another member, even one who can see the same savings, has no goal and sees none.  
  Evidence: `core/test/vv_f05_c_test.exs:157` no goal is supplied: none until the member sets one, and one member's goal is theirs alone; `app/test/vv_f05_c_test.exs:284` REQ-146: no goal is supplied; one member's goal isn't shown to another
- **AC-5** The System sets, prefills, and shows no goal value: until the member sets one, there is no goal, the goal field is empty, and no goal or progress is shown.  
  Evidence: `core/test/vv_f05_c_test.exs:157` no goal is supplied: none until the member sets one, and one member's goal is theirs alone; `app/test/vv_f05_c_test.exs:284` REQ-146: no goal is supplied; one member's goal isn't shown to another
- **AC-6** The page offers no suggested number of months for the goal.  
  Evidence: `app/test/vv_f05_c_test.exs:284` REQ-146: no goal is supplied; one member's goal isn't shown to another

*Notes:* AC-6 needs a human ruling: the goal field's placeholder reads 'e.g. 3' (app/lib/findependence_app/web/html.ex goals_page), while the hint says 'nothing here suggests one'. Whether an example value in a placeholder is 'a target supplied by the System' is not decidable from the statement. Every other criterion passes.

### REQ-147 · Verified

- **AC-1** A member can set, and remove, a set-aside rate for money in linked to a value they can see.  
  Evidence: `app/test/v03_web_test.exs:283` REQ-146/147: how long savings would last, the member's goal, and a set-aside rate; `core/test/plans_projection_test.exs:229` a set-aside rate on money in linked to a value; one-offs and other members' links don't count
- **AC-2** A rate for a value the member can't see is refused.  
  Evidence: `core/test/plans_projection_test.exs:229` a set-aside rate on money in linked to a value; one-offs and other members' links don't count
- **AC-3** The member sees the monthly amount the rate sets aside from the repeating money in linked to that value by their own links.  
  Evidence: `app/test/v03_web_test.exs:283` REQ-146/147: how long savings would last, the member's goal, and a set-aside rate; `core/test/plans_projection_test.exs:229` a set-aside rate on money in linked to a value; one-offs and other members' links don't count
- **AC-4** The rate is private: another member has no set-aside from it.  
  Evidence: `core/test/plans_projection_test.exs:229` a set-aside rate on money in linked to a value; one-offs and other members' links don't count

*Notes:* One-off money in is not counted in the monthly amount (a monthly figure); the tests assert this, and it is read as part of 'the monthly amount'. No new test was needed.

### REQ-148 · Verified

- **AC-1** A member can propose one of their own plans to other members as a shared plan (a snapshot item of kind plan); they can't propose another member's plan.  
  Evidence: `core/test/plans_projection_test.exs:262` a snapshot item; the named member joins only by agreeing; it isn't money; `app/test/v03_web_test.exs:322` REQ-148: a plan proposed to another member is shared only when they agree; `core/test/vv_f05_c_test.exs:220` only the member's own plan can be proposed
- **AC-2** A named member becomes an owner only with their own consent.  
  Evidence: `core/test/plans_projection_test.exs:262` a snapshot item; the named member joins only by agreeing; it isn't money; `app/test/v03_web_test.exs:322` REQ-148: a plan proposed to another member is shared only when they agree
- **AC-3** With several members named, one's consent makes no one an owner; each becomes an owner only once every named member and owner has agreed.  
  Evidence: `core/test/vv_f05_c_test.exs:189` proposed to two members: each becomes an owner only once both have agreed; each sees the plan meanwhile
- **AC-4** With several current owners, a named member becomes an owner only with every current owner's consent too.  
  Evidence: `core/test/vv_f05_c_test.exs:205` with two owners, a member joins only with their own agreement and every current owner's
- **AC-5** Until they agree, a named member sees the proposal and the plan's steps (once every current owner has agreed, per REQ-167).  
  Evidence: `app/test/v03_web_test.exs:322` REQ-148: a plan proposed to another member is shared only when they agree; `core/test/vv_f05_c_test.exs:189` proposed to two members: each becomes an owner only once both have agreed; each sees the plan meanwhile; `core/test/vv_f05_c_test.exs:205` with two owners, a member joins only with their own agreement and every current owner's
- **AC-6** A shared plan's steps never change: not on consent, not when the plan it came from is changed or deleted, not when an item a step names is deleted, not when an owner leaves it, and no member can add or remove a step of it.  
  Evidence: `core/test/vv_f05_c_test.exs:225` a shared plan's steps never change

*Notes:* AC-5 follows REQ-167, which supersedes REQ-102: with several current owners, the joiner sees the proposal once every current owner has agreed. The interface offers no form to add an owner to an existing shared plan; AC-4 is tested at the core, which the generic /act/owners route calls.

### REQ-149 · Verified

- **AC-1** A member can add an account of type 401(k) and of type IRA; both are offered where accounts are added.  
  Evidence: `app/test/v04_web_test.exs:94` REQ-149: a 401(k) is an account with a balance, but never cash; `app/test/v04_web_test.exs:232` REQ-149/150: an IRA can be added; 15% is the highest return; a zero contribution clears it; `core/test/vv_f05_d_test.exs:32` retirement_401k and ira: created owned by the creator alone, private, with name and kind fixed
- **AC-2** A new 401(k) or IRA is owned by its creator alone, with no grantees, and no other member can see it.  
  Evidence: `core/test/vv_f05_d_test.exs:32` retirement_401k and ira: created owned by the creator alone, private, with name and kind fixed; `app/test/vv_f05_d_test.exs:239` REQ-149: an IRA shared with someone shows them its latest balance only, and they can't update it
- **AC-3** Its name and kind never change: it can't be re-created under the same id, and adding readings, sharing, changing owners, revoking, and relinquishing leave its name and kind as created.  
  Evidence: `core/test/vv_f05_d_test.exs:32` retirement_401k and ira: created owned by the creator alone, private, with name and kind fixed
- **AC-4** Any owner, including one of joint owners, adds a dated balance reading without anyone's consent; readings are append-only (earlier ones kept unchanged), validated like any account's, and each is recorded in the item's history.  
  Evidence: `core/test/vv_f05_d_test.exs:50` retirement_401k and ira: any owner adds a dated reading without consent; append-only and in the history
- **AC-5** A member it is shared with can't add a reading (refused, nothing saved, in core and at the interface); a member who can't see it is told it isn't there.  
  Evidence: `core/test/vv_f05_d_test.exs:82` retirement_401k and ira: someone it's shared with can't add a reading; someone who can't see it is told it isn't there; `app/test/vv_f05_d_test.exs:239` REQ-149: an IRA shared with someone shows them its latest balance only, and they can't update it
- **AC-6** Owners read every reading; a member it is shared with reads only the latest (and its page shows no earlier balances); nobody else reads any, including after sharing stops.  
  Evidence: `core/test/vv_f05_d_test.exs:92` retirement_401k and ira: owners read every reading; someone it's shared with only the latest; nobody else any; `app/test/vv_f05_d_test.exs:239` REQ-149: an IRA shared with someone shows them its latest balance only, and they can't update it
- **AC-7** Each reading has its own key, sealed only to the members AC-6 allows; a member who stops being able to see it loses their keys and is never sealed a later reading; a reader written into the file without the app is never sealed one.  
  Evidence: `app/test/vv_f05_d_test.exs:269` REQ-149 (REQ-133): each IRA reading has its own key, sealed only to those who may read it; `app/test/readings_crypto_test.exs:147` a reader written into the file by editing it is never sealed a reading, and it's reported
- **AC-8** The item rules REQ-130/REQ-171 name apply as to any item: the owner's export carries it with its readings and a grantee's doesn't; an owner can't leave while owning it; a joint owner can't delete it alone; a pending proposal can be withdrawn; the sole owner's deletion removes it and its readings.  
  Evidence: `core/test/vv_f05_d_test.exs:111` retirement_401k and ira: deletion, export, leaving, and withdrawing apply as to any item; `core/test/retirement_test.exs:121` deleting the account removes contributions to it; leaving removes the assumptions
- **AC-9** A retirement account's balance is never counted as cash: not in the running balance, not in the next twelve months, and not in how long savings would last.  
  Evidence: `core/test/retirement_test.exs:48` are accounts with readings, but never cash; `app/test/v04_web_test.exs:94` REQ-149: a 401(k) is an account with a balance, but never cash

*Notes:* AC-3 ('fixed') rests on there being no operation that edits an item's name or kind; the test shows the operations that exist leave them unchanged, which is the observable form. AC-7's third clause (a reader edited into the file) is type-independent code and is cited from the checking/debt test, not re-run for an IRA. AC-8 samples the item rules of REQ-171 (REQ-101..REQ-110, REQ-125, REQ-167, REQ-169); REQ-167/169 access and export are otherwise type-independent. At the interface a grantee's view of earlier balances is guarded three times (core readings, per-reading keys, and the page showing earlier balances to owners only): the interface test fails only when all three are broken.

### REQ-150 · Verified

- **AC-1** A member can save a birth year, a retirement age, a yearly return, a monthly contribution to each retirement account they can see, a monthly Social Security estimate, and a monthly target income.  
  Evidence: `app/test/v04_web_test.exs:109` REQ-150/151: assumptions saved together; the projection with its assumptions stated; `app/test/vv_f05_d_test.exs:296` REQ-150: every assumption, including birth year, Social Security, and target, is cleared by an empty field
- **AC-2** They are private: kept in the member's own record, another member's session can't read them, and another member's page doesn't show them; each member's are their own.  
  Evidence: `app/test/v04_web_test.exs:109` REQ-150/151: assumptions saved together; the projection with its assumptions stated; `core/test/retirement_test.exs:67` are private, validated, clearable, and never filled in
- **AC-3** A contribution can be set only for a retirement account the member can see (not a cash account, not one they can't see), and stops counting once they can't see it.  
  Evidence: `core/test/retirement_test.exs:108` contributions go only to retirement accounts the member can see; `core/test/retirement_test.exs:175` only the retirement accounts the member can see, and their own contributions
- **AC-4** The return is accepted from -5% to 15% inclusive and refused outside that range.  
  Evidence: `core/test/retirement_test.exs:67` are private, validated, clearable, and never filled in; `app/test/v04_web_test.exs:162` REQ-150: invalid values are refused at the field, with what was typed kept; `app/test/v04_web_test.exs:232` REQ-149/150: an IRA can be added; 15% is the highest return; a zero contribution clears it
- **AC-5** Each is optional: saving with any of them empty is accepted.  
  Evidence: `app/test/v04_web_test.exs:109` REQ-150/151: assumptions saved together; the projection with its assumptions stated; `app/test/vv_f05_d_test.exs:389` REQ-154: no retirement page suggests an investment, a product, or a value; every state passes the judgment-word and glossary checks
- **AC-6** Each can be cleared: birth year, retirement age, return, each contribution, Social Security estimate, and target all become unset (in core with nil; at the interface with an empty field).  
  Evidence: `core/test/vv_f05_d_test.exs:143` birth year, retirement age, return, Social Security, target, and a contribution; `app/test/vv_f05_d_test.exs:296` REQ-150: every assumption, including birth year, Social Security, and target, is cleared by an empty field; `app/test/v04_web_test.exs:232` REQ-149/150: an IRA can be added; 15% is the highest return; a zero contribution clears it
- **AC-7** An invalid value in any field (birth year, age, return, contribution, Social Security, target) is refused at that field, nothing is saved, and what was typed is shown again in every field for correction.  
  Evidence: `app/test/v04_web_test.exs:162` REQ-150: invalid values are refused at the field, with what was typed kept; `app/test/vv_f05_d_test.exs:330` REQ-150: an invalid birth year, Social Security estimate, or contribution is refused, with what was typed kept; `core/test/retirement_test.exs:67` are private, validated, clearable, and never filled in
- **AC-8** Nothing is filled in or suggested by the System (interpretation): on the form every assumption field starts empty, with no placeholder, list of options, select, or datalist; the retirement pages carry no recommending phrase (REQ-154 AC-3).  
  Evidence: `app/test/vv_f05_d_test.exs:369` REQ-150/154: nothing is filled in or offered in any assumption field; `core/test/retirement_test.exs:67` are private, validated, clearable, and never filled in; `app/test/vv_f05_d_test.exs:389` REQ-154: no retirement page suggests an investment, a product, or a value; every state passes the judgment-word and glossary checks
- **AC-9** Deleting a retirement account removes every member's contribution to it; a member who leaves has their assumptions removed.  
  Evidence: `core/test/retirement_test.exs:121` deleting the account removes contributions to it; leaving removes the assumptions

*Notes:* AC-8 is an interpretation of 'suggested'. Field error messages give format examples after an invalid entry ('Enter the year you were born, like 1968.', 'Enter a yearly return from -5 to 15, like 5 or 4.5.', 'Enter an amount like 62.40 or 1,200.'). Under this interpretation a format example shown only after an invalid entry is not a suggested value; that reading is not ratified (human gate requested). A typed 0 contribution clears it at the interface while core refuses 0 (DEF-045, by design).

### REQ-151 · Verified

- **AC-1** Without a birth year, a retirement age, and a return there is no projection, and the page says which are needed.  
  Evidence: `core/test/retirement_test.exs:138` needs a birth year, a retirement age, and a return; `app/test/v04_web_test.exs:109` REQ-150/151: assumptions saved together; the projection with its assumptions stated
- **AC-2** With them, the page shows the balance year by year from this month until January of the year the member reaches that age (no rows when that is this year or earlier).  
  Evidence: `core/test/retirement_test.exs:146` month by month from the latest balances to January of the retirement year; `core/test/retirement_test.exs:197` an account without a balance yet counts from zero; retiring this year or earlier means no rows; `app/test/v04_web_test.exs:109` REQ-150/151: assumptions saved together; the projection with its assumptions stated
- **AC-3** It starts from the latest balances of the retirement accounts the member can see (an account with no balance counts as zero), and only those.  
  Evidence: `core/test/retirement_test.exs:175` only the retirement accounts the member can see, and their own contributions; `core/test/retirement_test.exs:197` an account without a balance yet counts from zero; retiring this year or earlier means no rows
- **AC-4** Each month it grows at the return and adds that month's contributions (exact values checked against an independent calculation).  
  Evidence: `core/test/retirement_test.exs:146` month by month from the latest balances to January of the retirement year
- **AC-5** The page says the result is in today's dollars and states the assumptions next to the result: the starting balances and dates, the monthly contribution, the return, and the age.  
  Evidence: `app/test/v04_web_test.exs:109` REQ-150/151: assumptions saved together; the projection with its assumptions stated

*Notes:* 'In today's dollars' is a statement about the inputs (the return is after inflation); it is verified as what the page states, not as an economic property.

### REQ-153 · Verified

- **AC-1** The balance at retirement is shown with the return two percentage points lower and higher, and retiring two years earlier and later, each worked out with that one change.  
  Evidence: `core/test/retirement_test.exs:240` the return two points either way and retiring two years either way; nothing saved; `app/test/v04_web_test.exs:254` REQ-153: each alternative is labelled with the assumption it changes
- **AC-2** For each of those alternatives, how long the balance would last paying the difference is shown, worked out with that one change (years and months with the age, 'no difference to pay', or 'some remains at 100').  
  Evidence: `core/test/vv_f05_d_test.exs:207` each alternative says how long it would last, worked out with that one change; `app/test/vv_f05_d_test.exs:435` REQ-153: each alternative says how long it would last, beside the result
- **AC-3** The alternatives are shown beside the result as entered: on the same page, in one table whose first row is the result as entered.  
  Evidence: `app/test/v04_web_test.exs:196` REQ-152/153: compared with the member's own target; what changes the result; `app/test/vv_f05_d_test.exs:435` REQ-153: each alternative says how long it would last, beside the result
- **AC-4** Nothing about the alternatives is saved: the member's assumptions are unchanged after they are worked out and shown.  
  Evidence: `core/test/retirement_test.exs:240` the return two points either way and retiring two years either way; nothing saved; `core/test/vv_f05_d_test.exs:207` each alternative says how long it would last, worked out with that one change

*Notes:* Alternatives outside the allowed ranges (a return above 15% or below -5%, an age above 90 or below 40) are left out without saying so (core/test/retirement_test.exs:266); the statement is silent on this, so it is neither required nor forbidden (specification gap, not a defect).

### REQ-154 · Verified

- **AC-1** No assumption field on a retirement page is prefilled or offers values: every field starts empty, with no placeholder, list, select, or datalist (interpretation of 'suggest' for contributions, returns, ages, and targets).  
  Evidence: `app/test/vv_f05_d_test.exs:369` REQ-150/154: nothing is filled in or offered in any assumption field; `app/test/v04_web_test.exs:109` REQ-150/151: assumptions saved together; the projection with its assumptions stated
- **AC-2** No retirement page names an investment or a product (interpretation: none of a fixed list of investment and product terms, such as index fund, mutual fund, target-date, annuity, ETF, stock, bond, Roth, brokerage, CD, or fund-company names, appears in its visible text).  
  Evidence: `app/test/vv_f05_d_test.exs:389` REQ-154: no retirement page suggests an investment, a product, or a value; every state passes the judgment-word and glossary checks
- **AC-3** No retirement page contains a recommending sentence (interpretation: none of a fixed list of recommending forms, such as should, recommend, suggest, consider, advise, try to, aim for, better, best, ideal, enough, on track, behind, appears in its visible text, apart from the page's own disclaimer that nothing is advice or a suggestion).  
  Evidence: `app/test/vv_f05_d_test.exs:389` REQ-154: no retirement page suggests an investment, a product, or a value; every state passes the judgment-word and glossary checks; `app/test/v04_web_test.exs:274` REQ-154: no suggestions and no judgment words on the retirement pages
- **AC-4** The judgment-word and glossary checks pass on every retirement page: the retirement page with nothing set, with assumptions missing, with a result, with a result that outlasts age 100, with Social Security covering the target, refused with errors, for a member with no retirement account, and a retirement account's own page.  
  Evidence: `app/test/vv_f05_d_test.exs:389` REQ-154: no retirement page suggests an investment, a product, or a value; every state passes the judgment-word and glossary checks; `app/test/v04_web_test.exs:274` REQ-154: no suggestions and no judgment words on the retirement pages

*Notes:* 'Suggest' has no observable definition in the statement; AC-1..AC-3 are the interpretation, and a phrase list can only show the absence of the phrases it names, so AC-3 is only as good as its list. Not treated as suggestions (human gate requested to ratify): the format examples in field errors (REQ-150 notes); the ±2 alternatives, which REQ-153 requires; 'add one as a 401(k) or an IRA' shown to a member with no retirement account, which names the two account kinds the app records rather than recommending a product. 'Every retirement page' is taken to be /retirement in all its states and a retirement account's page.

### REQ-155 · Verified

- **AC-1** The file names its format and version.  
  Evidence: `core/test/import_test.exs:186` carries the member's own plans, marks, goals, and retirement, and nothing of anyone else's; `app/test/v05_web_test.exs:141` REQ-155/DEF-032: the saved file is versioned, even for a member who owns a shared plan
- **AC-2** It carries the member's own plans with their steps.  
  Evidence: `core/test/import_test.exs:186` carries the member's own plans, marks, goals, and retirement, and nothing of anyone else's
- **AC-3** It carries the member's marks on items they own.  
  Evidence: `core/test/import_test.exs:186` carries the member's own plans, marks, goals, and retirement, and nothing of anyone else's; `core/test/vv_f05_d_test.exs:408` nothing in it belongs to anyone else
- **AC-4** It carries the member's goals: the fund goal and set-aside rates.  
  Evidence: `core/test/import_test.exs:186` carries the member's own plans, marks, goals, and retirement, and nothing of anyone else's; `core/test/vv_f05_d_test.exs:408` nothing in it belongs to anyone else
- **AC-5** It carries all of the member's retirement assumptions: birth year, retirement age, return, Social Security estimate, target, and contributions.  
  Evidence: `core/test/vv_f05_d_test.exs:408` nothing in it belongs to anyone else; `core/test/import_test.exs:186` carries the member's own plans, marks, goals, and retirement, and nothing of anyone else's
- **AC-6** A set-aside for a value the member doesn't own, and a contribution to an account they don't own, are left out.  
  Evidence: `core/test/import_test.exs:222` leaves out set-asides and contributions for what the member doesn't own
- **AC-7** Marks, plan steps, and links that name an entry the member doesn't own (relinquished, deleted, or only shared with them) are left out, and every reference left in the file names an entry in it.  
  Evidence: `core/test/vv_f05_d_test.exs:376` marks, plan steps, and links naming entries the member doesn't own are left out
- **AC-8** Nothing in it belongs to anyone else (interpretation): no item the member doesn't own, and none of another member's links, marks, plans, goals, retirement assumptions, or attachments, even where they name the member's items.  
  Evidence: `core/test/vv_f05_d_test.exs:408` nothing in it belongs to anyone else; `core/test/import_test.exs:186` carries the member's own plans, marks, goals, and retirement, and nothing of anyone else's

*Notes:* AC-8 treats an item the member co-owns as theirs: REQ-169 exports owned items with their owners, grantees, ledger, and readings, so a co-owner's ledger entries and readings on a jointly owned item are in the file by design (VV-001 recorded this as a specification note on REQ-155's wording).

### REQ-156 · Verified

- **AC-1** A member can bring an export into the household they belong to, by checking it, seeing the preview, and confirming.  
  Evidence: `app/test/v05_web_test.exs:176` REQ-156/158: check, preview, then bring in as the member's alone; `core/test/import_test.exs:237` everything becomes the member's alone, and works the same as before
- **AC-2** Every item, value, account, and debt in the file becomes a new entry (none keeps an id from the file), owned by the member alone, with no grantees.  
  Evidence: `core/test/import_test.exs:237` everything becomes the member's alone, and works the same as before; `core/test/vv_f05_d_test.exs:486` links, marks, plan steps, set-asides, contributions, and readings name the new entries; `core/test/vv_f05_d_test.exs:516` no history, owners, or sharing from the old household: each history starts with the bringing in; `app/test/v05_web_test.exs:176` REQ-156/158: check, preview, then bring in as the member's alone
- **AC-3** Accounts' and debts' readings come in on the new entries, with the same dates and values.  
  Evidence: `core/test/vv_f05_d_test.exs:486` links, marks, plan steps, set-asides, contributions, and readings name the new entries
- **AC-4** Links between entries in the file join the corresponding new entries.  
  Evidence: `core/test/vv_f05_d_test.exs:486` links, marks, plan steps, set-asides, contributions, and readings name the new entries
- **AC-5** Plans (their steps), marks, goals (set-asides), retirement assumptions (contributions), and attachments name the new entries.  
  Evidence: `core/test/vv_f05_d_test.exs:486` links, marks, plan steps, set-asides, contributions, and readings name the new entries; `core/test/import_test.exs:237` everything becomes the member's alone, and works the same as before
- **AC-6** Goals and assumptions the member already set are kept; only unset ones are filled from the file.  
  Evidence: `core/test/import_test.exs:319` goals and assumptions already set are kept; only unset ones are filled
- **AC-7** Owners, sharing, and history from the old household are not brought in: each new entry's history has only its creation by the member and the readings they brought in.  
  Evidence: `core/test/vv_f05_d_test.exs:516` no history, owners, or sharing from the old household: each history starts with the bringing in
- **AC-8** Shared plans are not brought in.  
  Evidence: `core/test/import_test.exs:237` everything becomes the member's alone, and works the same as before; `app/test/v05_web_test.exs:176` REQ-156/158: check, preview, then bring in as the member's alone
- **AC-9** The member is told that owners, sharing, history, and shared plans are not brought in (on the preview), and that only they own what came in (after confirming).  
  Evidence: `app/test/vv_f05_d_test.exs:521` REQ-156: the member is told that owners, sharing, history, and shared plans aren't brought in; `app/test/v05_web_test.exs:176` REQ-156/158: check, preview, then bring in as the member's alone
- **AC-10** Each new entry's history begins with its being brought in by the member.  
  Evidence: `core/test/import_test.exs:237` everything becomes the member's alone, and works the same as before; `core/test/vv_f05_d_test.exs:516` no history, owners, or sharing from the old household: each history starts with the bringing in; `app/test/v05_web_test.exs:176` REQ-156/158: check, preview, then bring in as the member's alone

*Notes:* AC-9: the preview says 'Its history, owners, and who it was shared with in the other household stay in your file.' This is read as telling the member they are not brought in (interpretation).

### REQ-157 · Verified

- **AC-1** A file of more than 1 MB (1,048,576 bytes) is refused, before it is read when the upload itself is over the limit; a file of exactly 1 MB is checked.  
  Evidence: `app/test/v05_web_test.exs:321` REQ-157: a file that fails a check is refused whole, saying what and where; `app/test/v05_web_test.exs:352` REQ-157: a body over the limit is refused before it is read; `app/test/vv_f05_d_test.exs:560` REQ-157: a file of exactly 1 MB is checked; one byte more is refused
- **AC-2** A file that isn't valid JSON is refused.  
  Evidence: `app/test/v05_web_test.exs:321` REQ-157: a file that fails a check is refused whole, saying what and where
- **AC-3** A file of an unknown format or version is refused.  
  Evidence: `core/test/import_test.exs:405` anything wrong refuses the whole file, saying what and where
- **AC-4** Every field is checked: amounts in whole cents within range, known frequencies and kinds, valid dates and months, names within length, and references that resolve within the file; unknown fields are refused.  
  Evidence: `core/test/import_test.exs:405` anything wrong refuses the whole file, saying what and where; `core/test/import_test.exs:501` a fault is reported once, where it is, and not again at what refers to it
- **AC-5** The checks are the same rules as entering by hand: a value the interface accepts when typed by hand is accepted in the file, and one it refuses is refused.  
  Evidence: `app/test/wi059_test.exs:172` what hand entry accepts, the member's file brings back (19 cases: names and amounts at every form's limits); `core/test/import_test.exs:405` anything wrong refuses the whole file, saying where and what (the file refuses what hand entry refuses)
- **AC-6** If any check fails, nothing is brought in, and the member is told what failed and where in the file.  
  Evidence: `app/test/v05_web_test.exs:321` REQ-157: a file that fails a check is refused whole, saying what and where; `core/test/import_test.exs:405` anything wrong refuses the whole file, saying what and where
- **AC-7** Nothing in the file creates an atom or runs: unknown keys and values never become atoms, and names from the file are shown as text, never markup or script.  
  Evidence: `core/test/import_test.exs:510` a file can't create atoms, and at most 20 problems are reported; `app/test/v05_web_test.exs:321` REQ-157: a file that fails a check is refused whole, saying what and where; `app/test/v05_web_test.exs:383` REQ-158: names from the file are shown as text, never as markup

*Notes:* AC-5 fails: hand entry has no name length limit, allows an empty name, and has no upper limit on amounts, while the file check refuses names over 200 characters, empty names, and amounts over 1,000,000,000.00. So a member's own saved file is refused. Reproduced by three temporary interface tests (removed, as instructed): unlock as ana; on home add an item named with 201 letters 'a', amount 10, money out, monthly (saved, 303); or named '' (empty), amount 5, money in, monthly (saved; stored note ''); or named 'Lottery', amount 1,000,000,001, money in, one-off (saved). Then GET /export.json and upload that file at /bring-in (as ben or ana): 422, 'Nothing was brought in', with 'Number 3 in the file, name: must be 1 to 200 characters of text.' (long or empty name) or 'Number 3 in the file, amount: isn't an amount in whole cents within range.' Whether hand entry or the file check should change is an upstream decision (Defeater proposed, not filed). 1 MB is read as 1,048,576 bytes, as the implementation does (interpretation).

### REQ-158 · Indeterminate

- **AC-1** Before anything is saved, the preview counts the items, values, accounts, debts, readings, links, plans, marks, and goals the file would bring in.  
  Evidence: `app/test/v05_web_test.exs:176` REQ-156/158: check, preview, then bring in as the member's alone; `app/test/vv_f05_d_test.exs:538` REQ-158: the preview counts debts and goals, with the debts' names
- **AC-2** The preview names what becomes the member's: the items, values, accounts, debts, and plans, by name, shown as text.  
  Evidence: `app/test/v05_web_test.exs:176` REQ-156/158: check, preview, then bring in as the member's alone; `app/test/vv_f05_d_test.exs:538` REQ-158: the preview counts debts and goals, with the debts' names; `app/test/v05_web_test.exs:383` REQ-158: names from the file are shown as text, never as markup
- **AC-3** Nothing is saved while the preview is shown.  
  Evidence: `app/test/v05_web_test.exs:176` REQ-156/158: check, preview, then bring in as the member's alone; `app/test/vv_f05_d_test.exs:538` REQ-158: the preview counts debts and goals, with the debts' names
- **AC-4** In a browser, choosing 'Bring it in' on the preview brings the file in.  
  Evidence: `app/test/v05_web_test.exs:176` REQ-156/158: check, preview, then bring in as the member's alone; `app/test/v05_web_test.exs:255` REQ-158 (DEF-046): the browser fetching the tab icon, or an image, is not leaving the preview
- **AC-5** Choosing Cancel, or locking, saves nothing.  
  Evidence: `app/test/v05_web_test.exs:300` REQ-158: cancelling, or locking, brings nothing in
- **AC-6** Leaving the preview for another page saves nothing, and its form sent afterwards brings nothing in.  
  Evidence: `app/test/v05_web_test.exs:255` REQ-158 (DEF-044): leaving the preview drops the file; its form then brings nothing in

*Notes:* AC-4 is asserted at the HTTP level only. Since WI-056 any request other than the bring-in routes drops the waiting file, including requests a browser makes by itself. Reproduced with a temporary test (removed): upload a valid file (preview, 200); GET /favicon.ico with the same session cookie (404); then POST /act/bring-in/confirm with the preview's _csrf_token and _form: redirected to /bring-in, 'Nothing is waiting to be brought in', nothing saved. Pages have no icon link, and headed Chrome and Firefox usually request /favicon.ico after such a page loads, which would make 'Bring it in' fail in real use. Headless Chromium 154 here made no favicon request, so the browser effect is not observed in this environment. It needs a check in a headed browser (another environment): probable defect, Defeater proposed, not filed. 'The names of what becomes theirs' is read as the named entries (items, values, accounts, debts, plans); readings, links, marks, and goals have no names and are counted. Still Indeterminate: AC-4 is shown with simulated background fetches (the tab icon, Sec-Fetch-Dest image), not in a headed browser, which is the case that matters; a one-minute check in WALKTHROUGH-001 resolves it.

### REQ-159 · Verified

- **AC-1** The same file (byte for byte) brought in a second time by the same member is refused, saying the date it was brought in before, and nothing changes.  
  Evidence: `core/test/import_test.exs:362` is refused with the date it was brought in, and changes nothing; `app/test/v05_web_test.exs:176` REQ-156/158: check, preview, then bring in as the member's alone
- **AC-2** Only that is refused: a different file, or the same file by another member, is not.  
  Evidence: `core/test/import_test.exs:362` is refused with the date it was brought in, and changes nothing
- **AC-3** Bringing a record in changes nothing anyone else owns or can see: their visible items and the items they own are unchanged, and none of what came in is visible to them.  
  Evidence: `core/test/import_test.exs:237` everything becomes the member's alone, and works the same as before; `app/test/v05_web_test.exs:176` REQ-156/158: check, preview, then bring in as the member's alone

*Notes:* 'The same file' is read as identical bytes (the implementation keeps a SHA-256 fingerprint); a copy of the same record whose bytes differ is not refused. 'By mistake' has no further observable meaning.

### REQ-160 · Verified

- **AC-1** A member can say which account a money item goes through: a checking, savings, or 'other' account.  
  Evidence: `core/test/attach_test.exs:52` any money item and cash account the member can see; privately; clearable; `core/test/attach_test.exs:140` an item the member owns but says goes through another account leaves this one; `core/test/vv_f05_c_test.exs:280` an 'other' account can be chosen; an IRA can't; `app/test/vv_f05_c_test.exs:318` REQ-160: an 'other' account is offered, and choosing a different account replaces the first
- **AC-2** A retirement account (401(k) or IRA) or a debt can't be chosen.  
  Evidence: `core/test/attach_test.exs:64` not to what they can't see, not a value or balance, and not to a debt or retirement account; `core/test/vv_f05_c_test.exs:280` an 'other' account can be chosen; an IRA can't; `app/test/cp014_web_test.exs:151` REQ-160: a debt can't be chosen, and the reason is given
- **AC-3** Any money item and account the member can see qualify, including ones others share with them; anything they can't see, and values, accounts, or debts as the item, are refused.  
  Evidence: `core/test/attach_test.exs:52` any money item and cash account the member can see; privately; clearable; `core/test/attach_test.exs:64` not to what they can't see, not a value or balance, and not to a debt or retirement account; `core/test/vv_f05_c_test.exs:288` an account someone shares with the member can be chosen
- **AC-4** The member can change it to a different account, which replaces the first.  
  Evidence: `core/test/vv_f05_c_test.exs:294` changing to a different account replaces the first; `app/test/vv_f05_c_test.exs:318` REQ-160: an 'other' account is offered, and choosing a different account replaces the first
- **AC-5** The member can clear it.  
  Evidence: `core/test/attach_test.exs:52` any money item and cash account the member can see; privately; clearable; `app/test/cp014_web_test.exs:114` REQ-160/161: choosing the account counts a shared paycheck in Coming up; clearing it stops
- **AC-6** Only the member sees it.  
  Evidence: `core/test/attach_test.exs:52` any money item and cash account the member can see; privately; clearable; `app/test/cp014_web_test.exs:114` REQ-160/161: choosing the account counts a shared paycheck in Coming up; clearing it stops
- **AC-7** Deleting the item or the account removes it.  
  Evidence: `core/test/attach_test.exs:76` deleting the item or the account removes it; losing sight of either stops it counting; leaving removes all
- **AC-8** Leaving removes all of the member's own, including where the item and the account remain in the household.  
  Evidence: `core/test/vv_f05_c_test.exs:300` leaving removes all of the member's own, even where the item and account remain

*Notes:* 'Cash account' is read by the statement's parenthesis: checking, savings, or other, not a retirement account.

### REQ-161 · Verified

- **AC-1** Home's Coming up covers the next fourteen days: today to today + 13; something dated today + 14 is not shown.  
  Evidence: `app/test/vv_f05_c_test.exs:394` the next fourteen days: the thirteenth day after today is in, the fourteenth isn't; `core/test/vv_f05_c_test.exs:315` fourteen days: today to today + 13
- **AC-2** It shows at most the first four days that have something on them, in date order.  
  Evidence: `app/test/vv_f05_c_test.exs:354` at most the first four days with something on them, in date order, then how many more days
- **AC-3** When more such days follow in the fourteen, it says how many (one day, several days); with four or fewer it says nothing more.  
  Evidence: `app/test/vv_f05_c_test.exs:354` at most the first four days with something on them, in date order, then how many more days
- **AC-4** It links to the full view (the next 60 days).  
  Evidence: `app/test/vv_f05_c_test.exs:388` a way to the full view
- **AC-5** The items shown are the dated items that count for the member: items they said go through one of their visible checking accounts, and items they own and haven't said go through any account; an item they said goes through another account doesn't count; an item others only share with them counts only once they say so.  
  Evidence: `core/test/attach_test.exs:124` sharing alone isn't enough, and information shared with a parent isn't their money; `core/test/attach_test.exs:140` an item the member owns but says goes through another account leaves this one; `core/test/attach_test.exs:108` sharing and attaching every item that goes through it gives both the same balance, every day; `app/test/cp014_web_test.exs:114` REQ-160/161: choosing the account counts a shared paycheck in Coming up; clearing it stops
- **AC-6** With a visible checking account that has a reading, it shows the running balance of the member's visible checking accounts after each day; savings and accounts they can't see are not included; without one, no balance is shown.  
  Evidence: `core/test/schedule_test.exs:102` days below zero can be found; savings and other members' accounts don't count; `core/test/schedule_test.exs:72` no checking reading: dated items listed, no balance; `app/test/cash_flow_web_test.exs:90` REQ-138: coming up lists the next 14 days, and a running balance once checking has one
- **AC-7** The balance starts from the sum of those accounts' latest readings and applies every dated occurrence after the most recent of those readings' dates.  
  Evidence: `core/test/schedule_test.exs:79` starts from the latest reading and applies only what comes after its date; `core/test/schedule_test.exs:93` an older reading counts what happened between it and today; `core/test/schedule_test.exs:115` two checking accounts: summed, from the most recent reading's date
- **AC-8** The page says which accounts and which date the balance starts from.  
  Evidence: `app/test/cash_flow_web_test.exs:90` REQ-138: coming up lists the next 14 days, and a running balance once checking has one
- **AC-9** For an account others also own, the page names them and says their items may not be counted.  
  Evidence: `app/test/ux002_test.exs:29` R1a: a joint account's view names whose items it leaves out; a member's own account doesn't; `app/test/ux004_test.exs:180` P2: a joint account's view is labelled as the member's part; a member's own account isn't

*Notes:* 'Next fourteen days' is read as fourteen days starting today (today + 0 to today + 13), as the code does.

### REQ-162 · Verified

- **AC-1** The member sees each of the next twelve months, starting with the month after this one.  
  Evidence: `core/test/plans_projection_test.exs:49` months start after this one; cash runs from the account balances; one-offs land in their month; `app/test/v03_web_test.exs:106` REQ-141: the next 12 months, with cash, debts, and the assumptions stated
- **AC-2** Money in and out counts the items that count for them: those they said go through one of the cash accounts the projection starts from, and those they own and haven't said go through any account.  
  Evidence: `core/test/attach_test.exs:140` an item the member owns but says goes through another account leaves this one; `core/test/attach_test.exs:155` the same months for both parents once every item through the joint account is shared and attached
- **AC-3** Repeating items count at their per-month amounts; a dated one-off counts in its own month only; an undated one-off counts in no month.  
  Evidence: `core/test/plans_projection_test.exs:49` months start after this one; cash runs from the account balances; one-offs land in their month; `core/test/vv_f05_c_test.exs:374` an undated one-off is in no month; a dated one-off only in its own
- **AC-4** Cash at the end of each month starts from the latest balances of the cash accounts they can see.  
  Evidence: `core/test/plans_projection_test.exs:49` months start after this one; cash runs from the account balances; one-offs land in their month; `app/test/v03_web_test.exs:106` REQ-141: the next 12 months, with cash, debts, and the assumptions stated
- **AC-5** Each debt they can see (their own or shared with them) grows each month by a month's interest and falls by its minimum payment.  
  Evidence: `core/test/plans_projection_test.exs:60` debts grow by a month's interest and fall by the minimum; `core/test/vv_f05_c_test.exs:354` a debt someone shares with the member is one of their debts; one they can't see isn't
- **AC-6** Until paid off: the last payment is only what is owed, the balance reaches zero and stays there with no further interest, and the month it is paid off is shown.  
  Evidence: `core/test/vv_f05_c_test.exs:332` a debt reaching payoff stops: it falls to zero and stays there, with no more interest; `app/test/vv_f05_c_test.exs:401` REQ-162: a debt paid off within the twelve months shows the month and nothing owed after
- **AC-7** The page states these assumptions next to the results, and each stated assumption matches what is counted.  
  Evidence: `app/test/v03_web_test.exs:106` REQ-141: the next 12 months, with cash, debts, and the assumptions stated; `app/test/wi058_test.exs:49` DEF-048: the twelve months say they count shared items attached to the member's accounts
- **AC-8** For an account others also own, the page names them and says their items may not be counted.  
  Evidence: `app/test/ux002_test.exs:29` R1a: a joint account's view names whose items it leaves out; a member's own account doesn't

*Notes:* DEFECT (AC-7): /ahead states 'repeating items you own count at their per-month amount' and 'It counts only items you own' (html.ex @assumptions, from REQ-141), but under REQ-162 an item others share with the member counts once the member says it goes through one of the accounts. Reproduced: ben's monthly paycheck of 1,980 shared with ana and attached by ana to her checking; ana's /ahead shows October In +$1,980.00 while stating 'It counts only items you own'. The page also shows the correct sentence ('Counts items you own, and items shared with you that you've said go through these accounts'), so it contradicts itself. Every other criterion passes.

### REQ-164 · Verified

- **AC-1** The saved file carries which account each item goes through, where the member owns both the item and the account, and leaves out attachments where they don't.  
  Evidence: `core/test/import_test.exs:331` only those where the member owns both come out, and they come back on the new entries
- **AC-2** Bringing the file in restores those attachments between the new entries.  
  Evidence: `core/test/import_test.exs:331` only those where the member owns both come out, and they come back on the new entries; `core/test/vv_f05_d_test.exs:486` links, marks, plan steps, set-asides, contributions, and readings name the new entries
- **AC-3** The file names its format version as 3.  
  Evidence: `core/test/import_test.exs:186` carries the member's own plans, marks, goals, and retirement, and nothing of anyone else's; `app/test/v05_web_test.exs:141` REQ-155/DEF-032: the saved file is versioned, even for a member who owns a shared plan
- **AC-4** Files of earlier versions (1 and 2) still come in, without attachments (a version 2 file naming attachments is refused).  
  Evidence: `core/test/vv_f05_d_test.exs:540` a version 2 file (no attachments) is brought in whole, with no attachments; `core/test/import_test.exs:342` a version 2 file has none, and an attachment must name a money item and a cash account in the file; `core/test/import_test.exs:525` files from before version 2 still come in, where an empty amount was written as 'nil'

*Notes:* None.

### REQ-165 · Verified

- **AC-1** Every form that changes the household (each of the 27 such actions other than Leave, whose session ends with it; see AC-3), sent again from the same page after the first sending finished (a repeated click, a resend, or going back and sending it again, however many other forms came between, in the same session), leaves the stored file byte-for-byte unchanged, returns to where the first went, and says 'That was already saved.'  
  Evidence: `app/test/vv_f05_b_test.exs:867` every form that changes the household changes it once, and a repeat says it was already saved; `app/test/ux004_test.exs:89` P1 (REQ-165): a form sent twice changes the household once, and the repeat says so; `app/test/wi052_test.exs:127` DEF-041: a form resent after 70 later forms changes nothing and says so
- **AC-2** A second sending that arrives while the first is still being handled changes nothing; the household is changed once. Interpretation: it is told 'That was already sent. Check below that it was saved.' (the outcome is not known yet), and a repeat after the first finished is told it was already saved.  
  Evidence: `app/test/vv_f05_b_test.exs:996` a second click while the first is still being handled changes nothing
- **AC-3** A form that changed the household, sent again after the session ended (after Lock and unlocking, after the idle lock, or a second click on Leave that arrives after the first finished), changes nothing and says it was already saved.  
  Evidence: `app/test/wi059_repeat_test.exs:110` after locking and unlocking again, resending a saved form says it was already saved; `app/test/wi059_repeat_test.exs:121` after the idle lock and the sweep, resending a saved form says it was already saved; `app/test/wi059_repeat_test.exs:132` after the idle lock, before the sweep, resending a saved form says it was already saved; `app/test/wi059_repeat_test.exs:169` a second click on Leave that arrives after the member left says it was already done
- **AC-4** A form whose first sending was refused (a mistake in a field, or a rule such as an unknown member) may be sent again, corrected, and is then saved, not taken for a repeat.  
  Evidence: `app/test/ux004_test.exs:152` P1 (REQ-165): a refused form changed nothing, so the same form may be sent again, corrected; `app/test/vv_f05_b_test.exs:1030` a form refused by a rule may be sent again, corrected, and is then saved
- **AC-5** A form whose first sending arrived after the session had ended changes nothing and is not remembered: sent again in a live session with that session's CSRF token, it is saved, not taken for a repeat.  
  Evidence: `app/test/vv_f05_b_test.exs:1044` a form sent after the session ended changed nothing, and its one-time token isn't kept

*Notes:* DEFECT (AC-3): the household is changed at most once in every case, but a repeat sent after the session ended is told the opposite of 'already saved'. Reproduce, each from a fresh vault with members ana and ben: (a) unlock as ana; on home, add a value 'Home'; press Lock; unlock as ana; go back to the earlier page and send the add-value form again (same _csrf_token and _form): 403 'That wasn't saved. This page was out of date, so nothing was saved. Go to the home page and do it again.' (b) unlock as ana; add a value 'Home'; leave the session idle over 15 minutes until the sweep runs; send the same form again: redirect to /?locked=action, 'Locked after 15 minutes without use. Your last action was not saved. Unlock and do it again.' (c) unlock as a member who owns nothing; open /leave; press 'Leave the household' twice, the second arriving after the first finished (it carries the same cookie): the second is answered /?locked=replaced, 'You were locked out, so your last action was not saved. Unlock and do it again.' Cause: one-time form tokens are remembered per session (sessions.ex claim_form), so once a session ends a saved form is no longer recognized, and the refusal pages (DEF-035, WI-032, UX-001 R4) say nothing was saved. Following the advice to do it again would make a second, deliberate change. The failing test was removed. AC-2 wording: the statement says a repeat shall 'say that it was already saved'; while the first sending is still in progress that can't truthfully be said, and the app says it was already sent; this is flagged for the Requirement's owner, not counted as a defect. A crafted request with no form token from an unlocked session is refused (wi052_test.exs:156); a browser always sends one.

### REQ-166 · Verified

- **AC-1** Deleting an item (an item of money in or out, an account, or a debt) from its page first shows a page that names it ('Delete “Name”?'), says its history goes with it, and asks to confirm; the only delete form is on that page, and no page offers deleting straight away.  
  Evidence: `app/test/vv_f05_b_test.exs:1085` deleting a value, an item, an account, or a debt is first shown by name and asked; going back keeps it; `app/test/vv_f05_b_test.exs:1156` no page offers deleting straight away; the leaving checklist names the item and asks for an explicit choice; `app/test/web_ux_test.exs:155` delete goes through a confirmation page; leaving through the checklist
- **AC-2** Deleting a value does the same.  
  Evidence: `app/test/vv_f05_b_test.exs:1085` deleting a value, an item, an account, or a debt is first shown by name and asked; going back keeps it
- **AC-3** Deleting a plan first shows its name and how many steps go with it, and asks to confirm. Interpretation: 'by name' means the plan is named; steps have no names, so they are counted.  
  Evidence: `app/test/ux004_test.exs:216` P3 (REQ-166): deleting a plan is previewed by name and confirmed; going back keeps it; `app/test/vv_f05_b_test.exs:1127` a plan with steps is named, with how many steps go with it; going back keeps it
- **AC-4** Going back leaves it unchanged: showing the confirmation changes nothing in the file, and following 'No, go back' leads to a page where it is still there.  
  Evidence: `app/test/vv_f05_b_test.exs:1085` deleting a value, an item, an account, or a debt is first shown by name and asked; going back keeps it; `app/test/vv_f05_b_test.exs:1127` a plan with steps is named, with how many steps go with it; going back keeps it; `app/test/ux004_test.exs:216` P3 (REQ-166): deleting a plan is previewed by name and confirmed; going back keeps it
- **AC-5** Interpretation for the leaving checklist (UX-001 R8, where the checklist is the confirmation): deleting from it needs an explicit choice, 'Delete it for everyone (can't be undone)', beside the item's name ('What happens to “Name”'), from a required list that starts with nothing chosen; sent with no choice, nothing is deleted.  
  Evidence: `app/test/vv_f05_b_test.exs:1156` no page offers deleting straight away; the leaving checklist names the item and asks for an explicit choice
- **AC-6** Removing a single plan step or a single link does not ask: the form on the page posts straight to the removal, and one press removes it.  
  Evidence: `app/test/vv_f05_b_test.exs:1215` removing one plan step or one link doesn't ask: one press removes it

*Notes:* Confirmation is an interface safeguard; the handler deletes on a direct POST by design (DEF-042), so the criteria are about what the pages offer. AC-5 is an interpretation for the Requirement's owner to confirm: the leaving checklist names the item and needs a deliberate choice, but shows no separate confirmation page. The item delete page's 'No, go back' leads home, not to the item's page; the statement does not say where going back leads.

### REQ-167 · Verified

- **AC-1** An owner can read the item.  
  Evidence: `core/test/household_test.exs:37` owner reads; `core/test/randomized_test.exs:303` visible iff owner or grantee, after every step
- **AC-2** A member holding an active grant can read it.  
  Evidence: `core/test/household_test.exs:45` a grantee reads the item; `core/test/randomized_test.exs:20`
- **AC-3** A member being added as an owner of a value by a pending proposal every current owner has agreed to can read the value.  
  Evidence: `core/test/shared_value_test.exs:25` the joiner sees the value's attributes after every owner consented; `app/test/vault_test.exs:117` and can open its key
- **AC-4** The same for a shared plan.  
  Evidence: `core/test/plans_projection_test.exs:262` the named member sees the plan's attributes; `core/test/vv_f05_a_test.exs:518` after every current owner agreed
- **AC-5** Nobody else can read it: not a member with no role, a former grantee or owner, an invitee to a value or shared plan before every current owner agreed, or a member named in a pending owner change on an ordinary item or in a pending grant. An invisible item reads exactly like a missing one, in the core and on the item page.  
  Evidence: `core/test/household_test.exs:37` others cannot, and invisible looks like missing; `core/test/household_test.exs:73` a revoked grantee; `core/test/household_test.exs:88` a removed owner; `core/test/shared_value_test.exs:25` value invitee before every owner consented; `core/test/vv_f05_a_test.exs:518` shared plan invitee before every owner agreed; `core/test/vv_f05_a_test.exs:503` named in a pending proposal on an ordinary item, or in a pending grant; `app/test/vault_test.exs:117` no key before every owner consents; `app/test/vv_f05_a_test.exs:106` an item page for an invisible item equals the one for a missing id
- **AC-6** An invitee's access ends when the proposal is withdrawn.  
  Evidence: `core/test/exit_test.exs:146` after withdrawal the invitee sees nothing; `app/test/vault_test.exs:183` withdrawing removes the access given in advance

*Notes:* Interpretation: 'read an item' = see its attributes (View.get and lists for owners and grantees; the pending proposal for an invitee) or open its key in the app.

### REQ-168 · Verified

- **AC-1** A member can link any money item visible to them (one they own alone or jointly, or one shared with them; recurring, one-off, or irregular) to any value visible to them (their own, one they share, or one shared with them by grant).  
  Evidence: `core/test/alignment_test.exs:36` a member links visible items to visible values; `core/test/vv_f05_a_test.exs:565` every such pair links (5 items x 3 values)
- **AC-2** They can unlink any of their links.  
  Evidence: `core/test/alignment_test.exs:63` unlink removes only one's own link; `core/test/vv_f05_a_test.exs:565` every link unlinks
- **AC-3** A value, an account or debt, or a shared plan cannot be linked as the item.  
  Evidence: `core/test/alignment_test.exs:49` a value is a target, not an activity; `core/test/balances_test.exs:113` an account; `core/test/plans_projection_test.exs:262` a shared plan; `core/test/vv_f05_a_test.exs:583` values, an account, a debt, a shared plan
- **AC-4** Links belong to the member who made them: two members link the same item independently, and nobody else can unlink them.  
  Evidence: `core/test/alignment_test.exs:56` two members link the same shared item differently, each privately; `core/test/alignment_test.exs:63` another member's unlink is refused
- **AC-5** No other member can ever read them: another member's link list, distribution, and export are unchanged by them, even when both ends are visible to that member or later owned by them; and in the stored file they can't be opened by another member.  
  Evidence: `core/test/alignment_test.exs:36` nobody else sees the link; `core/test/randomized_test.exs:454` each member's links are exactly their own stored links; `core/test/vv_f05_a_test.exs:605` even once they own both ends; `app/test/crypto_properties_test.exs:126` another member's secrets can't open the personal record; `app/test/vault_test.exs:133` links private to their member

*Notes:* Interpretation: 'visible' = owned or held by an active grant. An invitee who can read a value's proposal (REQ-167) can't link to it before joining; the statement's 'visible' is not read to include that. 'Ever' is tested for the ways a member can come to see or own both ends, not proved.

### REQ-169 · Verified

- **AC-1** Export needs nobody else's consent: it is produced at once and asks nothing of anyone.  
  Evidence: `core/test/exit_test.exs:67` export returned directly; `core/test/vv_f05_a_test.exs:730` no proposal is created
- **AC-2** It contains every item the member currently owns, alone or jointly, of every kind (money, value, account, debt, shared plan), and no other item.  
  Evidence: `core/test/exit_test.exs:67` exactly the owned items, not items shared by grant; `core/test/randomized_test.exs:402` exactly the owned items after every step; `core/test/vv_f05_a_test.exs:730` exact list of 8 items of every kind
- **AC-3** Each with its attributes, owners, grantees, and history.  
  Evidence: `core/test/exit_test.exs:67` owners and ledger; `core/test/vv_f05_a_test.exs:730` attributes, owners, grantees, and ledger for each item
- **AC-4** For an account or debt, its readings.  
  Evidence: `core/test/balances_test.exs:125` an owner's export carries them; `core/test/vv_f05_a_test.exs:730` account and debt readings
- **AC-5** The member's own links whose item and value they both currently own, and no other link.  
  Evidence: `core/test/alignment_test.exs:260` own links between owned ends only; `core/test/alignment_test.exs:274` another member's links never; `core/test/randomized_test.exs:413` after every step; `core/test/vv_f05_a_test.exs:730`
- **AC-6** The member's own plans, marks, goals, and retirement assumptions.  
  Evidence: `core/test/import_test.exs:186` carries the member's own plans, marks, goals, and retirement; `core/test/vv_f05_a_test.exs:730` exact plans, marks, goals, retirement
- **AC-7** Which account each item goes through.  
  Evidence: `core/test/import_test.exs:331` attachments where the member owns both; `core/test/vv_f05_a_test.exs:730`
- **AC-8** In those (plans, marks, goals, retirement, attachments) only references to entries the export contains are kept: plan steps, marks, set-asides, contributions, and attachments naming anything not exported are dropped.  
  Evidence: `core/test/import_test.exs:222` leaves out set-asides and contributions for what the member doesn't own; `core/test/vv_f05_a_test.exs:730` switch-off steps, marks, set-asides, contributions, attachments filtered
- **AC-9** Nothing else: the export has exactly these parts, each item exactly these fields, and nothing of other members, deletion records, or pending proposals.  
  Evidence: `core/test/vv_f05_a_test.exs:730` exact keys and exact content

*Notes:* Interpretations: the export's identifying envelope (the member's own id; in the saved file, the format name and version, and each item's history in words, derived from its ledger) is not counted as additional content. 'Keeping only references' is read as applying to the listed personal parts, as the sentence is written; a shared plan is an item, and its attributes (a snapshot of steps) are exported as they are, so they may name items not in the export. That reading is flagged for the author of REQ-169; it is not treated as a defect. Tested in the core; the interface's /export.json encodes the same export (html.ex export_json).

### REQ-170 · Verified

- **AC-1** Every ledger entry is stored encrypted: no entry's event or details appear in the stored file in plaintext.  
  Evidence: `app/test/vault_test.exs:144` REQ-122: no attribute, label, link, or ledger detail appears in plaintext in the stored file; `app/test/vv_f05_b_test.exs:198` REQ-122: kinds, account and debt types, every kind of history entry, and plan names stay out of the file
- **AC-2** When an entry is appended, its key is sealed to exactly the item's owners at that moment, not to grantees.  
  Evidence: `app/test/vv_f05_b_test.exs:1280` each ledger entry is sealed to the owners when it is appended, and re-sealed to each new owner; `app/test/vault_test.exs:106` REQ-120: ledger entries are readable by owners only, and re-sealed for new owners
- **AC-3** Every existing entry is re-sealed for each member who becomes an owner, so they can open the whole ledger with their own secrets.  
  Evidence: `app/test/vv_f05_b_test.exs:1280` each ledger entry is sealed to the owners when it is appended, and re-sealed to each new owner; `app/test/vault_test.exs:106` REQ-120: ledger entries are readable by owners only, and re-sealed for new owners
- **AC-4** A prospective owner of a value can open every entry once every current owner has agreed to add them, before their own consent, and not while any current owner has yet to agree; if the proposal is withdrawn, the keys are removed.  
  Evidence: `app/test/vv_f05_b_test.exs:1304` a prospective owner of a value can read the whole ledger once every current owner agrees, not before; `app/test/vault_test.exs:117` REQ-119/120 with REQ-115: a prospective joiner can read a value only after every owner consents
- **AC-5** The same holds for a prospective owner of a shared plan.  
  Evidence: `app/test/vv_f05_b_test.exs:1326` so can a prospective owner of a shared plan; a proposed owner of anything else can't
- **AC-6** No other member can open an entry: not a grantee, not a proposed owner of any other kind of item, not a former owner (for earlier or later entries), not a withdrawn joiner, and not a member written into the file by editing it.  
  Evidence: `app/test/vv_f05_b_test.exs:1280` each ledger entry is sealed to the owners when it is appended, and re-sealed to each new owner; `app/test/vv_f05_b_test.exs:1292` an owner who relinquishes loses their ledger keys and gets none for later entries; `app/test/vv_f05_b_test.exs:1326` so can a prospective owner of a shared plan; a proposed owner of anything else can't; `app/test/vault_test.exs:183` REQ-125: withdrawing a value invitation removes the access the joiner was given in advance; `app/test/tamper_test.exs:54` ledger entries, old or new, are not sealed to a tampered-in owner either

*Notes:* Closes the REQ-120 gap (re-sealing to a joiner before their consent, now asserted positively). REQ-170's wording ('those members ... and no other member') removes the REQ-120 inconsistency VV-001 noted.

### REQ-171 · Verified

- **AC-1** Each listed kind (accounts: checking, savings, other, 401(k), IRA; debts: card, HELOC, loan, other) can be created and is an item of its own kind, account or debt, with its type; no other type is accepted.  
  Evidence: `core/test/vv_f05_b_test.exs:34` every listed kind can be created; it is owned by its creator alone and private
- **AC-2** It is created by a member and owned by that member alone.  
  Evidence: `core/test/vv_f05_b_test.exs:34` every listed kind can be created; it is owned by its creator alone and private; `core/test/balances_test.exs:18` private by default, owned by the creator, with a fixed name and kind
- **AC-3** It is private by default: no other member can see it until shared.  
  Evidence: `core/test/vv_f05_b_test.exs:34` every listed kind can be created; it is owned by its creator alone and private; `core/test/balances_test.exs:18` private by default, owned by the creator, with a fixed name and kind
- **AC-4** The rules of REQ-101, REQ-103, REQ-105..REQ-108, REQ-110, REQ-125, REQ-167, and REQ-169 hold for accounts and debts as for any item, each exercised on an account and on a debt.  
  Evidence: `core/test/vv_f05_b_test.exs:58` REQ-101, REQ-103, REQ-105, REQ-107: owners, grants, and history work as for any item; `core/test/vv_f05_b_test.exs:98` REQ-106: a household view counts only accounts the member can see; `core/test/vv_f05_b_test.exs:106` REQ-108: only a sole owner deletes, and everything about it goes but a bare record; `core/test/vv_f05_b_test.exs:125` REQ-110: owning an account or a debt stops a member leaving until it's gone; `core/test/vv_f05_b_test.exs:138` REQ-125: a pending change to a joint account can be withdrawn by an owner; `core/test/vv_f05_b_test.exs:147` REQ-167: read if and only if owner or grantee; being proposed as an owner gives no access; `core/test/vv_f05_b_test.exs:161` REQ-169: the owner's export carries the account with its readings; a grantee's doesn't; `core/test/randomized_test.exs:20` REQ-101..114 and REQ-125 hold after every operation of 2000 seeded sequences; `core/test/balances_test.exs:29` sharing, ownership, and exit apply as to any item
- **AC-5** Its name and kind are fixed when it is created: no operation (readings, grants, owner changes, revocation, relinquishing, another member leaving) changes them, and it can't be added again under its id with another name or kind.  
  Evidence: `core/test/vv_f05_b_test.exs:170` its name and kind are fixed: no operation changes them

*Notes:* Closes the REQ-130 gap that 'fixed' rested only on the absence of an edit function. In the app, stored item content is written once and never re-encrypted (session.ex keeps the first content box; ASM-021), and no route changes an item's attributes; AC-5 is asserted at the core, through which every change passes. REQ-106 is inside 'REQ-105..REQ-108'.

### REQ-172 · Verified

- **AC-1** Each account has its own page showing its latest reading and the date it is as of.  
  Evidence: `app/test/balances_web_test.exs:73` adding an account, then its balance, from its own page
- **AC-2** Each debt has its own page showing its latest reading (owed, rate, minimum) and the date it is as of.  
  Evidence: `app/test/balances_web_test.exs:131` a debt: what's owed, the rate, the minimum, and a month's interest as a fact; `app/test/vv_f05_c_test.exs:465` a debt's page gives the date its latest reading is as of
- **AC-3** To its owners, the page offers what owners can do: update the balance, share it, change who owns it, give it away or delete it; others see none of these and are told only owners can.  
  Evidence: `app/test/vv_f05_c_test.exs:472` owners see what they can do and the earlier readings and history; someone it's shared with sees neither; `app/test/balances_web_test.exs:182` shared with someone: they see the latest only, and can't update it
- **AC-4** To its owners, the page shows earlier readings and history; others see only the latest reading.  
  Evidence: `app/test/balances_web_test.exs:182` shared with someone: they see the latest only, and can't update it; `app/test/vv_f05_c_test.exs:472` owners see what they can do and the earlier readings and history; someone it's shared with sees neither
- **AC-5** For a debt with a reading, the page states one month's interest at that rate on that balance, as a fact.  
  Evidence: `app/test/balances_web_test.exs:131` a debt: what's owed, the rate, the minimum, and a month's interest as a fact
- **AC-6** Home lists accounts and debts compactly, one row each (name, balance, owners, kind and as-of date), each name linking to its page.  
  Evidence: `app/test/vv_f05_c_test.exs:449` home lists each account and debt in one row that links to its page, with no account or debt forms; `app/test/balances_web_test.exs:73` adding an account, then its balance, from its own page
- **AC-7** Home has no account or debt forms (adding an account, adding a debt, or updating a balance).  
  Evidence: `app/test/balances_web_test.exs:63` home offers a place for balances without forms; the add page has one form for each kind; `app/test/vv_f05_c_test.exs:449` home lists each account and debt in one row that links to its page, with no account or debt forms

*Notes:* 'What its owners can do' is read as the page giving owners their actions (AC-3). 'Compactly' is read as one table row per account or debt with no controls (AC-6).

### REQ-173 · Verified

- **AC-1** The page covers the next sixty days: today to today + 59; something dated today + 60 is not shown.  
  Evidence: `app/test/vv_f05_c_test.exs:502` the fifty-ninth day after today is in, the sixtieth isn't; a day below zero on the last day is marked; `core/test/vv_f05_c_test.exs:324` sixty days: today to today + 59
- **AC-2** Day by day: the days are shown in date order, each with what is dated on it and the balance after it.  
  Evidence: `app/test/vv_f05_c_test.exs:502` the fifty-ninth day after today is in, the sixtieth isn't; a day below zero on the last day is marked; `core/test/schedule_test.exs:79` starts from the latest reading and applies only what comes after its date
- **AC-3** The balance is the running balance REQ-161 describes.  
  Evidence: `core/test/schedule_test.exs:79` starts from the latest reading and applies only what comes after its date; `core/test/schedule_test.exs:115` two checking accounts: summed, from the most recent reading's date; `core/test/attach_test.exs:108` sharing and attaching every item that goes through it gives both the same balance, every day
- **AC-4** Each day on which the balance would be below zero is marked, including days with nothing dated on them and the sixtieth day.  
  Evidence: `app/test/cash_flow_web_test.exs:135` REQ-139/140: the 60-day page names the days below zero and the set-asides; `app/test/vv_f05_c_test.exs:502` the fifty-ninth day after today is in, the sixtieth isn't; a day below zero on the last day is marked
- **AC-5** No other label or judgment is attached.  
  Evidence: `app/test/cash_flow_web_test.exs:135` REQ-139/140: the 60-day page names the days below zero and the set-asides; `app/test/glossary_test.exs:297` no page or message judges: no good, bad, risk, on track, over budget (ROADMAP-ALPHA section 3)

*Notes:* The 60-day horizon gap is closed (AC-1). AC-2 needs a human ruling: the page shows a row only for days that have something dated on them (days below zero without entries are named in the 'Below zero' line, not as rows). If 'day by day' means a row for every one of the sixty days, the implementation does not meet it; if it means day-by-day order with the running balance, it does and the tests assert it. VV-001 already records this as a specification defect for REQ-139, which REQ-173 supersedes. 'Day by day' ratified by ACT-001 (REV-070): a row for each dated day, with below-zero ranges covering the days between.

### REQ-174 · Verified

- **AC-1** Without a target income, none of this is shown; the page says a target is needed to compare with.  
  Evidence: `core/test/retirement_test.exs:224` no target means no comparison; Social Security at or over the target means nothing to pay; `app/test/v04_web_test.exs:109` REQ-150/151: assumptions saved together; the projection with its assumptions stated
- **AC-2** With a target, the page shows the monthly difference between the target and the Social Security estimate (none entered counts as none).  
  Evidence: `app/test/v04_web_test.exs:196` REQ-152/153: compared with the member's own target; what changes the result; `core/test/retirement_test.exs:208` how long the difference could be paid; `core/test/retirement_test.exs:224` no target means no comparison; Social Security at or over the target means nothing to pay
- **AC-3** How long the balance at retirement would last paying that difference each month while growing at the same return is worked out month by month and shown in years and months with the age reached.  
  Evidence: `core/test/retirement_test.exs:208` how long the difference could be paid; `app/test/v04_web_test.exs:196` REQ-152/153: compared with the member's own target; what changes the result
- **AC-4** When some would remain at age 100, the page says so instead.  
  Evidence: `core/test/retirement_test.exs:224` no target means no comparison; Social Security at or over the target means nothing to pay; `app/test/vv_f05_d_test.exs:457` REQ-174: 'some would remain at age 100' is said when the balance outlasts it
- **AC-5** When the Social Security estimate is at least the target, the page says it covers the target.  
  Evidence: `core/test/retirement_test.exs:224` no target means no comparison; Social Security at or over the target means nothing to pay; `app/test/v04_web_test.exs:196` REQ-152/153: compared with the member's own target; what changes the result
- **AC-6** No result is scored or labelled (interpretation: no judgment word, glossary violation, or recommending phrase appears on the page in any of these states).  
  Evidence: `app/test/v04_web_test.exs:274` REQ-154: no suggestions and no judgment words on the retirement pages; `app/test/vv_f05_d_test.exs:389` REQ-154: no retirement page suggests an investment, a product, or a value; every state passes the judgment-word and glossary checks
- **AC-7** No result is compared with a figure the member did not set, except REQ-153's alternatives: every amount and percentage on the page is one the member entered, a balance read from their accounts, one worked out from those, an alternative REQ-153 shows, or the stated rounding unit.  
  Evidence: `app/test/vv_f05_d_test.exs:473` REQ-174: every figure on the page is one the member set, one worked out from them, or an alternative REQ-153 shows

*Notes:* AC-7 is a sufficient observable form: if every figure on the page comes from the member's own inputs, their account balances, or REQ-153's alternatives, no result can be compared with a figure they did not set. Ages and years are not checked by it; 'age 100' is the horizon the statement itself names and '$100' is the rounding the page states. 'Labelled' is read as an evaluative label (interpretation).

