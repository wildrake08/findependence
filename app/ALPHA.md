# Testing the Findependence alpha

Thank you for trying Findependence. This is an **alpha**: an early version for internal testing.

## The one rule

**Use made-up data only.** Don't enter real amounts, real names of accounts or people, or anything
about your actual finances or household. Don't use a passphrase you use anywhere else. This version
hasn't had its independent security review yet, so treat everything you type as if others could
read it.

## Setting up

You need the project's development container, or a machine with Elixir 1.18+ and OTP 27+.

```sh
cd app
mix deps.get
mix findependence.setup ../try.vault Ana Ben Cy
```

Setup asks each person for a passphrase of at least 12 characters. What you type isn't kept on
screen.
The names are made up too; three people lets you try sharing and agreeing.

```sh
ERL_CRASH_DUMP_SECONDS=0 mix findependence.serve ../try.vault 4848
```

Open **http://localhost:4848/** in a browser on the same machine. If your editor forwards the port,
make sure the forwarded port is also 4848, or the app will refuse the page.

To try it as a different person, press **Lock**, then unlock as someone else. Only one person is
unlocked at a time.

## What to try

1. As Ana, add a few items with different schedules: rent every month, groceries every week, water
   every two months, insurance twice a year, something irregular (enter the total for a year), and a
   one-off. Try a mistyped amount, and try leaving "How often?" unset.
2. Add a value in your own words, open an item, and link it to that value. Look at the totals on the
   home page.
3. Share an item with Ben. Make another item owned by Ana and Ben together, then try sharing that one
   with Cy.
4. Lock, and unlock as Ben. Whatever is waiting for Ben should come first. Agree to it.
5. As Ana, ask Ben to co-own a value, then withdraw the request before Ben answers.
6. As Cy, choose **Leave the household…** and follow the checklist to the end.
7. Leave the app alone for 15 minutes, then try to do something.
8. Try it at phone width (your browser's device toolbar, about 390 pixels wide).

Anything else is welcome too. Confusion counts as a finding.

## Reporting a problem

Tell the person who invited you:

- what you did, step by step;
- what you expected;
- what you saw instead, with a screenshot if you like (the data is made up, so that's fine);
- the version: **v0.1.0-alpha**.

"I didn't understand what this meant" is as useful as "this broke".

## Starting over

Stop the server (Ctrl-C twice), delete the household file (`rm ../try.vault`), and run setup again.
There is no other way to reset, and no way to recover a forgotten passphrase.

## Known limits

- One person at a time on the device.
- Items can't be edited after they're added; delete and add again.
- Nobody can join a household after setup.
- There is no backup: deleting or losing the file loses everything in it.
- Run one copy of the app per household file.

More detail is in [README.md](README.md).
