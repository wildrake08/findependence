# Findependence local prototype

**Alpha testers: start with [ALPHA.md](ALPHA.md).** The alpha is internal testing with made-up
data only (REV-034).

This is a research prototype for STUDY-001. **It must not be used with a real household** until
it has had an independent security review (DEF-026), independent ethics review, and a
professional check of the Washington notes (GATE-016).

All data stays in one encrypted file on this device, and the server accepts connections only
from this device (127.0.0.1).

```sh
cd app
mix deps.get

# Create a household. Each person types their own passphrase privately; it is not echoed.
mix findependence.setup ../household.vault ana ben

# Start the local interface, then open http://127.0.0.1:4848/ in a browser on this device.
# ERL_CRASH_DUMP_SECONDS=0 stops a crash from writing unlocked keys to disk (self-review F-07).
ERL_CRASH_DUMP_SECONDS=0 mix findependence.serve ../household.vault 4848
```

## What a member can do

- **Add items** (money in or out), choosing how often each happens: every week, two weeks, month,
  two months, or three months; twice a year; every year; irregular (enter the total for a year); or
  one-off. There is no default.
- **Add values**, in their own words.
- **Open any item or value** to share it, stop sharing it, change who owns it, link it to a
  value, see its history, or give it away, stop owning it, or delete it. Changes to jointly owned
  things are requests that wait until every owner agrees; anything waiting for you comes first on
  the home page.
- **See totals by value:** money in and out per month (other schedules and irregular yearly totals
  are converted), with one-off items shown apart. Nothing is scored or judged.
- **Leave the household** from a checklist that lists what needs a new owner, offers the export
  first, and shows the leave button once you own nothing.
- **Record balances and debts** (v0.2): accounts and debts with a balance, and for debts an interest
  rate and minimum payment, updated by any owner. People it's shared with see only the latest.
- **Look ahead and plan** (v0.3): the next 12 months with cash and debt interest; private plans
  (switch items off, add planned items, borrow) compared with and without, never counted as real;
  marks for what depends on a job; a debt's what-if; an emergency fund goal and set-aside rates;
  and plans shared with others only when they agree.
- **Retirement** (v0.4): 401(k) and IRA accounts, never counted as cash; a year-by-year projection
  in today's dollars to a retirement age you choose, from assumptions only you see (return,
  contributions, a Social Security estimate from your statement, a target income); how long the
  difference could be paid; and what changes the result. Nothing is suggested.
- **Taking your record with you** (v0.5): the saved file now carries your plans, marks, goals, and
  retirement assumptions; bring it into another household from home (Leaving), where it is checked
  strictly, shown to you, and brought in only when you confirm, as entries only you own.
- **See what's coming up** (v0.2): give items the date they happen, and home shows the next 14 days
  with the running checking balance; a 60-day page shows any days below zero and what setting aside
  would cover bills that come a few times a year.

## Limits to know

- **One person at a time.** Logging in replaces any other session. A session locks after
  15 minutes idle.
- **Forgotten passphrases cannot be recovered.** There is no reset.
- **There is no backup.** If the device breaks or is lost, the household's data is gone. Each member
  can save an export of what they own. Copying the file is not a safe backup: restoring an old copy
  silently undoes later "stop sharing" decisions (self-review F-03, CP-010).
- **Membership is fixed at setup** (ASM-022, CP-009). People can leave but not join.
- **Items can't be edited** after they are added (ASM-021, CP-008). Delete and add again, if
  you are the only owner.
- **Run one copy per household file.** If a second copy changes the file, the first refuses its
  next change ("Nothing was saved") and shows the latest version, so nothing is overwritten
  (self-review F-16).

## What is encrypted, and what is not

- **Encrypted:** item contents, amounts and how often they happen, value labels, links, item
  histories, and deletion records. Each is readable only by the members allowed to see it.
- **Not encrypted** (ASM-020): member names, public keys, random item identifiers, who owns
  and who can see each item, and the shape of pending requests. The consent materials must say so.

## Tests

`mix test` runs the unit, model, tamper, interface, accessibility, and vocabulary tests, plus an
end-to-end test that starts the real server as its own process and uses it over loopback HTTP
(it needs `curl`). The core household rules have their own suite: `cd ../core && mix test`.
