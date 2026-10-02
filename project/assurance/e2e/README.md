# End-to-end checks over HTTP (WI-049)

`alpha_e2e.py` drives the real server the way a browser does: it reads each page, fills the form it
finds there, submits it, and checks what the member would see. It covers the core workflows of the
v0.7.0-alpha readiness assessment (unlocking and locking, items, values and totals, sharing and
ownership with consent, balances and debts, cash flow, plans, goals, retirement, deleting and giving
up, a form sent twice, leaving with one's record and bringing it into another household) and DEF-035
(a stale form on one shared browser). Python 3, standard library only.

It needs two fresh households, served on two ports. From `app/`, with made-up passphrases typed
when asked (setup doesn't echo them):

```sh
mix findependence.setup /tmp/e2e/main.vault Ana Ben Cy     # ana passphrase 1 / ben passphrase 2 / cy passphrase 33
mix findependence.setup /tmp/e2e/other.vault Cy Dee        # cy passphrase 33 / dee passphrase 4
ERL_CRASH_DUMP_SECONDS=0 mix findependence.serve /tmp/e2e/main.vault 4871 &
ERL_CRASH_DUMP_SECONDS=0 mix findependence.serve /tmp/e2e/other.vault 4872 &
python3 ../project/assurance/e2e/alpha_e2e.py 4871 4872 /tmp/e2e
```

**Since v0.8.4 (REQ-201, the 72-hour cooling-off)** the real server makes sharing, giving away, and deleting wait,
which these scenarios can't. So they run in two parts:

- `alpha_e2e.py`, every workflow above, against servers started with `MIX_ENV=test`, whose only difference is that
  the wait is off (`app/config/config.exs`);
- `alpha_e2e_cooling.py <port> <out dir>`, against a fresh household (Ana, Ben, Cy) on a normal (`MIX_ENV=dev`)
  server: what waits, that it says when, that nothing is shown early, withdrawing, and that leaving isn't held up.

What happens after the 72 hours is checked by the page and contract tests, which move a fixed clock.

Each check prints `PASS` or `FAIL`; `results.json` records them, and the exit status is 0 only if all
pass. Run it on fresh households: it adds items, and a second run on the same files finds them
already there. Dates are fixed in the scenarios (October 2026), and the cash-flow checks assume the
device's date is before then.
