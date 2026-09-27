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

**Or start from the demo family** instead of an empty household: `mix findependence.demo
../demo-family.vault` creates Dad, Mom, and three kids (Alex 20 and Blake 18 in college, Casey 16)
with bills, paychecks, Grandma's help with tuition, accounts and debts, dates set around today,
plans, goals, retirement accounts, and one request waiting for Dad. It prints each person's demo passphrase. Serve that file instead of
`try.vault`. **Every name, figure, and relationship in the demo is invented**, including who shares
what with whom; it exists to show the features, not to describe any real family.

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

New in v0.2:

9. **Balances and debts.** From home, choose **Add an account or debt**. Add a checking account and
   its balance, and a credit card with what's owed, its interest rate, and its minimum payment. Update
   a balance later from the account's page, then share an account with someone and see what they see.
10. **Dates.** When adding a bill or paycheck, give the date it happens. It then appears under
    **Coming up** on home, with the running checking balance after each day.
11. **The next 60 days.** Open it from Coming up: which days the balance would be below zero, and
    how much setting aside each month would cover bills that come a few times a year.

New in v0.3:

12. **The next 12 months.** Cash month by month, and each debt now and in a year, paying minimums.
13. **Plans.** Start a plan ("If Dad's job stops"): switch off a paycheck from a month, add a planned
    cost such as a health premium, borrow to bridge a gap, and compare with and without the plan.
    Plans never change your real numbers. As Dad in the demo, open Dad's plans.
14. **What depends on a job.** On a bill's page, mark it as depending on a paycheck; switching the
    paycheck off in a plan then switches the bill off too.
15. **A debt's what-if.** On a card's page, try an extra amount each month, or a different rate.
16. **Goals.** Set an emergency fund goal in months, and a set-aside rate for side-business income.
17. **Shared plans.** Ask someone to share a plan. As Mom in the demo, open Dad's request with
    "See the plan": it's worked out from Mom's own items. Then agree, or leave it waiting.
18. **Retirement.** Add a 401(k) or an IRA with its balance, then open Retirement from home and enter
    your own assumptions. Change the return or the retirement age and compare with "What changes the
    result". As Dad in the demo, see Dad's; as Mom, see the page before any are entered. The figures
    are only as good as the assumptions, and none is suggested.
19. **Taking your record with you.** As Alex in the demo (moving out), choose Leaving, "See everything
    you'd take with you", and save it as a file. Set up a new household for Alex with
    `mix findependence.setup`, serve it, and choose "Bring in a file you saved". Check what it shows
    before you bring it in. Try the same file twice, and try a file you've changed by hand.

Anything else is welcome too. Confusion counts as a finding.

## Reporting a problem

Tell the person who invited you:

- what you did, step by step;
- what you expected;
- what you saw instead, with a screenshot if you like (the data is made up, so that's fine);
- the version: **v0.3.0-alpha** (or the one on the page's tag, if different).

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
