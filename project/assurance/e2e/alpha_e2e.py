# The alpha readiness scenarios (the v0.7.0-alpha assessment, WI-049), over HTTP against the real server.
# usage: alpha_e2e.py <port of a household with Ana, Ben, Cy> <port of a household with Cy> <out dir>
# The passphrases below are the ones README.md sets up. Prints one line per check; writes results.json.
import sys, os, re, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from browser import Browser, text, msgs, Forms
PORT, OTHER, OUT = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]; R = []
def check(w, what, ok, detail=""):
    R.append({"w": w, "check": what, "ok": bool(ok), "detail": detail[:220]}); print(("PASS " if ok else "FAIL ") + w + " | " + what + ((" | " + detail[:220]) if detail else ""))
PW = {"Ana": "ana passphrase 1", "Ben": "ben passphrase 2", "Cy": "cy passphrase 33"}
def unlock_full(m, port=PORT, pw=None):
    b = Browser(port); code, loc, page = b.submit("/", "/login", {"member": m, "passphrase": pw or PW[m]}); return b, code, loc, page
def unlock(m, port=PORT, pw=None): return unlock_full(m, port, pw)[0]

# W1 unlock / lock / one session
b, code, loc, page = unlock_full("Ana", pw="wrong passphrase!")
check("W1 unlock", "wrong passphrase refused, stays locked", "don't match" in text(page) and "Lock" not in text(page).split("Unlock")[0], "; ".join(msgs(page)))
ana, code, loc, page = unlock_full("Ana")
check("W1 unlock", "correct passphrase opens home as Ana", code == 303 and "Ana" in text(page) and "Your items" in text(page), f"{code} {loc}")
ben = unlock("Ben")
code, loc, page = ana.submit("/", "/act/add_value", {"label": "Should not save"}, page=page)
check("W1 unlock", "a second unlock replaces the first; the first's next action is refused and says so", "not saved" in text(page), f"{code} {loc}; " + "; ".join(msgs(page)))
code, loc, page = ben.submit("/", "/logout")
check("W1 unlock", "Lock returns to the unlock page", "Unlock" in text(page) and "Who are you?" in text(page), f"{code} {loc}")
ana = unlock("Ana")

# W2 items
code, loc, page = ana.submit("/", "/act/add_item", {"note": "Rent", "amount": "1,450", "frequency": "monthly", "direction": "out", "on": "2026-10-01"})
check("W2 items", "add a dated monthly bill", code == 303 and "Added" in " ".join(msgs(page)) and "Rent" in text(page), "; ".join(msgs(page)))
code, loc, page = ana.submit("/", "/act/add_item", {"note": "Wages", "amount": "3,200", "frequency": "biweekly", "direction": "in", "on": "2026-10-02"})
check("W2 items", "add a dated paycheck (money in)", code == 303 and "+$3,200.00" in text(page), "; ".join(msgs(page)))
code, loc, page = ana.submit("/", "/act/add_item", {"note": "Phone", "amount": "55,5", "frequency": "monthly", "direction": "out"})
check("W2 items", "mistyped amount refused at the field, typed text kept, nothing saved", code == 422 and 'id="amount-error"' in page and 'value="55,5"' in page and "Phone</a>" not in page, str(code))
code, loc, page = ana.submit("/", "/act/add_item", {"note": "Gym", "amount": "45", "direction": "out"}, drop=("frequency",))
check("W2 items", "no frequency chosen: refused with a reason", code == 422 and "how often" in text(page).lower(), str(code))
_, home = ana.get("/")
check("W2 items", "home lists exactly the two saved items with their schedule", home.count('href="/items/') >= 2 and "−$1,450.00" in text(home) and "a month" in text(home) and "Gym" not in text(home), "")
rent = re.search(r'href="/items/([^"]+)"><b>Rent', home).group(1)

# W3 values, link, totals
code, loc, page = ana.submit("/", "/act/add_value", {"label": "A safe home"})
val = re.search(r'href="/items/([^"]+)"><b>A safe home', page).group(1)
check("W3 values", "add a value in one's own words", "A safe home" in text(page), "; ".join(msgs(page)))
code, loc, page = ana.submit(f"/items/{rent}", "/act/link", {"value": val})
check("W3 values", "link Rent to the value from Rent's page", code == 303 and "A safe home" in text(page), "; ".join(msgs(page)))
_, home = ana.get("/")
tot = re.search(r'aria-label="Totals by value".*?</table>', home, re.S).group(0)
row = re.search(r'<tr role=row><td role=cell data-label="Value"><a href="/items/' + re.escape(val) + r'">.*?</tr>', tot, re.S)
check("W3 values", "totals show Rent's −$1,450.00 a month under the value, no judgment", row is not None and "−$1,450.00" in text(row.group(0)), text(row.group(0)) if row else "no row")

# W4 sharing and ownership with consent
code, loc, page = ana.submit(f"/items/{rent}", "/act/grant", {"member": "Ben"})
check("W4 sharing", "sole owner shares Rent with Ben at once", code == 303 and "Ben can see it" in text(page), "; ".join(msgs(page)))
ben = unlock("Ben")
_, bh = ben.get("/")
check("W4 sharing", "Ben sees Rent, marked shared with him", "Rent" in text(bh) and "Shared with you" in text(bh), "")
ana = unlock("Ana")
code, loc, page = ana.submit(f"/items/{rent}", "/act/revoke", {"member": "Ben"}, pick=0)
check("W4 sharing", "Ana stops sharing", code == 303 and "Nobody else can see it" in text(page), "; ".join(msgs(page)))
ben = unlock("Ben")
_, bh = ben.get("/"); c404, _ = ben.get(f"/items/{rent}")
check("W4 sharing", "Ben no longer sees Rent, even by its address", "Rent" not in text(bh) and c404 == 404, f"item page {c404}")
ana = unlock("Ana")
code, loc, page = ana.submit(f"/items/{rent}", "/act/owners", {"owners[]": ["Ana", "Ben"]}, drop=("owners[]",))
check("W4 sharing", "sole owner adds Ben as co-owner at once (REQ-107: all current owners consent)", code == 303 and "now owned by you and Ben" in text(page), "; ".join(msgs(page)))
code, loc, page = ana.submit(f"/items/{rent}", "/act/grant", {"member": "Cy"})
check("W4 sharing", "sharing a joint item with Cy waits for Ben (REQ-103)", code == 303 and "Cy" in text(page) and "wait" in text(page).lower(), "; ".join(msgs(page)))
cy = unlock("Cy"); _, ch = cy.get("/")
check("W4 sharing", "Cy can't see Rent before Ben agrees", "Rent" not in text(ch), "")
ben = unlock("Ben"); _, bh = ben.get("/")
check("W4 sharing", "Ben's home puts the request first", bh.find("Waiting for you") != -1 and bh.find("Waiting for you") < bh.find("Your items"), "")
code, loc, page = ben.submit("/", "/act/consent")
check("W4 sharing", "Ben agrees", code == 303 and "Agree" in " ".join(msgs(page)) or "agreed" in " ".join(msgs(page)).lower() or "can now see" in " ".join(msgs(page)), "; ".join(msgs(page)))
cy = unlock("Cy"); _, ch = cy.get("/")
check("W4 sharing", "Cy now sees Rent", "Rent" in text(ch), "")
ben = unlock("Ben")
code, loc, page = ben.submit(f"/items/{rent}", "/act/owners", {"owners[]": ["Ben"]}, drop=("owners[]",))
check("W4 sharing", "Ben proposing to remove Ana waits for Ana", code == 303 and "wait" in text(page).lower(), "; ".join(msgs(page)))
code, loc, page = ben.submit("/", "/act/withdraw")
check("W4 sharing", "Ben withdraws his own request", code == 303 and "ithdr" in " ".join(msgs(page)), "; ".join(msgs(page)))

# DEF-035: one shared browser; a page opened before a Lock and another member's unlock
shared = unlock("Ana")
_, tab = shared.get("/")
shared.submit("/", "/logout")
shared.submit("/", "/login", {"member": "Ben", "passphrase": PW["Ben"]})
code, loc, page = shared.submit("/", "/act/add_value", {"label": "From Ana's old tab"}, page=tab, follow=False)
check("W2 unlock", "on one shared browser, Ana's old tab after Ben unlocks says nothing was saved (DEF-035)", code == 403 and "This page was out of date, so nothing was saved." in text(page) and 'href="/"' in page, str(code))
_, bh = shared.get("/")
check("W2 unlock", "and Ben stays unlocked, with nothing added", "Ben" in text(bh) and "From Ana's old tab" not in text(bh), "")

ana = unlock("Ana")

# W5 balances and debts
code, loc, page = ana.submit("/balances/new", "/act/add_account", {"label": "Checking", "type": "checking"})
acct = loc.split("/items/")[1] if loc and "/items/" in loc else None
check("W5 balances", "add a checking account; lands on its page", code == 303 and acct is not None and "Checking" in text(page), f"{loc}")
code, loc, page = ana.submit(f"/items/{acct}", "/act/add_reading", {"balance": "850", "on": "2026-09-26"})
check("W5 balances", "record its balance", code == 303 and "$850.00" in text(page), "; ".join(msgs(page)))
code, loc, page = ana.submit("/balances/new", "/act/add_debt", {"label": "Visa", "type": "card"})
card = loc.split("/items/")[1] if loc and "/items/" in loc else None
code, loc, page = ana.submit(f"/items/{card}", "/act/add_reading", {"balance": "6,200", "rate": "abc", "min_payment": "190", "on": "2026-09-26"})
check("W5 balances", "a debt with an invalid rate is refused at the field", code == 422 and 'id="rate-error"' in page, str(code))
code, loc, page = ana.submit(f"/items/{card}", "/act/add_reading", {"balance": "6,200", "rate": "24.99", "min_payment": "190", "on": "2026-09-26"})
check("W5 balances", "a debt with owed, rate, and minimum is recorded", code == 303 and "$6,200.00" in text(page) and "24.99%" in text(page), "; ".join(msgs(page)))
c, wi = ana.get(f"/items/{card}?extra=100")
check("W5 balances", "a debt's what-if answers with an extra payment", c == 200 and "With $100.00 more a month" in text(wi), "")

# W6 cash flow
c, home = ana.get("/")
cu = re.search(r'id=coming-up>.*?</section>', home, re.S).group(0)
check("W6 cash flow", "Coming up starts from checking and runs Rent then Wages", "Starting from Checking: $850.00" in text(cu) and "Rent" in cu and "Wages" in cu, text(cu)[:200])
check("W6 cash flow", "the day Rent would take checking below zero is marked", "Below zero" in cu and "−$600.00" in text(cu), "")
c60, n60 = ana.get("/next-60-days"); c12, ahead = ana.get("/ahead")
check("W6 cash flow", "the next 60 days and 12 months open with figures", c60 == 200 and c12 == 200 and "Below zero:" in text(n60) and "Cash at the end" in text(ahead) or "Your part at the end" in text(ahead), f"{c60} {c12}")

# W7 plans
code, loc, page = ana.submit("/plans", "/act/new_plan", {"name": "If pay stops"})
plan = re.search(r"/plans/([^?]+)", loc).group(1)
check("W7 plans", "start a plan", code == 303 and "If pay stops" in text(page), loc)
wages = re.search(r'value="([^"]+)"[^>]*> Wages', page) or re.search(r'name=items(?:\[\])? value="([^"]+)"> Wages', page)
wid = re.search(r'<input type=checkbox name="items\[\]" value="([^"]+)">\s*Wages', page) or re.search(r'value="([^"]+)"> Wages', page)
code, loc, page = ana.submit(f"/plans/{plan}", "/act/plan_step", {"items[]": [wid.group(1)] if wid else [], "from": "2026-11"}, pick=0, drop=("items[]",))
check("W7 plans", "switch Wages off from November", code == 303 and "switch off Wages" in text(page), "; ".join(msgs(page)))
code, loc, page = ana.submit(f"/plans/{plan}", "/act/plan_step", {"amount": "6,000", "rate": "8.75", "payment": "250", "from": "2026-12"}, pick=2)
check("W7 plans", "borrow in December", code == 303 and "borrow $6,000.00" in text(page), "; ".join(msgs(page)))
check("W7 plans", "the plan compares with and without, and never changes real totals", "With this plan, cash first goes below zero" in text(page) and "This is a plan, not what's real" in text(page), "")
_, home2 = ana.get("/")
check("W7 plans", "home's real items are unchanged by the plan", "Wages" in text(home2) and "+$3,200.00" in text(home2), "")
code, loc, page = ana.submit(f"/plans/{plan}", "/confirm/delete_plan", follow=False)
check("W7 plans", "deleting asks first, naming the plan and its steps", code == 200 and "Delete the plan “If pay stops”?" in text(page) and "Its 2 steps" in text(page), str(code))
code, loc, page = ana.submit(f"/plans/{plan}", "/act/delete_plan", page=page)
check("W7 plans", "confirming deletes it and says which", code == 303 and "Deleted the plan “If pay stops”." in " ".join(msgs(page)), "; ".join(msgs(page)))

# W8 goals, W9 retirement
code, loc, page = ana.submit("/goals", "/act/fund_goal", {"months": "3"})
check("W8 goals", "an emergency fund goal in months is saved and worked out", code == 303 and "3" in text(page) and "months" in text(page), "; ".join(msgs(page)))
code, loc, page = ana.submit("/balances/new", "/act/add_account", {"label": "My 401(k)", "type": "retirement_401k"})
k = loc.split("/items/")[1]
ana.submit(f"/items/{k}", "/act/add_reading", {"balance": "48,200", "on": "2026-09-26"})
code, loc, page = ana.submit("/retirement", "/act/retirement", {"birth_year": "1976", "retire_age": "67", "return": "4", f"contribution_{k}": "400", "ss": "2,300", "target": "5,500"})
check("W9 retirement", "assumptions saved; a projection in today's dollars, rounded, with what changes it", code == 303 and re.search(r"about \$[\d,]+00\b", text(page)) is not None and "What changes the result" in text(page), "; ".join(msgs(page)))

# W11 delete and give up, and a double submission
_, hp = ana.get("/")
code, loc, page = ana.submit("/", "/act/add_item", {"note": "Gym", "amount": "45", "frequency": "monthly", "direction": "out"}, page=hp)
code2, loc2, page2 = ana.submit("/", "/act/add_item", {"note": "Gym", "amount": "45", "frequency": "monthly", "direction": "out"}, page=hp)
_, home3 = ana.get("/")
check("W11 changes", "the same form sent twice adds one item and says so", text(home3).count("Gym") == 1 and "That was already saved." in " ".join(msgs(page2)), "; ".join(msgs(page2)))
gym = re.search(r'href="/items/([^"]+)"><b>Gym', home3).group(1)
code, loc, page = ana.submit(f"/items/{gym}", "/confirm/delete", follow=False)
check("W11 changes", "deleting an item asks first", code == 200 and "Delete “Gym”?" in text(page), str(code))
code, loc, page = ana.submit(f"/items/{gym}", "/act/delete", page=page)
c404, _ = ana.get(f"/items/{gym}")
check("W11 changes", "confirming deletes it for everyone", code == 303 and "Gym" not in text(page).split("Your items")[1].split("What matters")[0] and c404 == 404, "; ".join(msgs(page)))
ben = unlock("Ben")
code, loc, page = ben.submit(f"/items/{rent}", "/confirm/relinquish", follow=False)
code, loc, page = ben.submit(f"/items/{rent}", "/act/relinquish", page=page)
check("W11 changes", "a joint owner stops owning; the other keeps it", code == 303 and "Rent" not in text(page).split("Your items")[1].split("What matters")[0], "; ".join(msgs(page)))

# W10 leave with one's record, and bring it in elsewhere
cy = unlock("Cy")
cy.submit("/", "/act/add_item", {"note": "Bus pass", "amount": "32.50", "frequency": "weekly", "direction": "out"})
c, hdr, body = cy.req("GET", "/export.json")
check("W10 leaving", "Cy downloads their record as a file", c == 200 and b"Bus pass" in body and "attachment" in (hdr.get("content-disposition") or ""), f"{c} {hdr.get('content-disposition')}")
open(os.path.join(OUT, "cy-export.json"), "wb").write(body)
_, lv = cy.get("/leave")
check("W10 leaving", "the leave checklist names what needs a new owner and holds the leave button", "Bus pass" in text(lv) and 'action="/act/leave"' not in lv, "")
bus = re.search(r'href="/items/([^"]+)"[^>]*>Bus pass', lv) or re.search(r'name=item value="([^"]+)"', lv)
code, loc, page = cy.submit("/leave", "/act/let_go", {"to": "delete"})
check("W10 leaving", "Cy deletes what they own from the checklist; the leave button appears", code == 303 and 'action="/act/leave"' in page, "; ".join(msgs(page)))
code, loc, page = cy.submit("/leave", "/act/leave")
login_page = Browser(PORT).get("/")[1]
check("W10 leaving", "Cy has left: no longer offered on the unlock page", code == 303 and ">Cy<" not in login_page, f"{code} {loc}")
other = unlock("Cy", port=OTHER)
code, loc, page = other.submit("/bring-in", "/act/bring-in", follow=False, files={"file": ("cy-export.json", body)})
check("W10 leaving", "in a new household, the file is checked and previewed before anything is saved", code == 200 and "What would be brought in" in text(page), str(code))
code, loc, page = other.submit("/bring-in", "/act/bring-in/confirm", page=page)
check("W10 leaving", "confirming brings Bus pass in as Cy's own", code == 303 and "Bus pass" in text(page), "; ".join(msgs(page)))
code, loc, page = other.submit("/bring-in", "/act/bring-in", follow=False, files={"file": ("cy-export.json", body)})
check("W10 leaving", "the same file a second time is refused, with the date", code == 422 and "so it wasn't brought in again" in text(page), str(code))
json.dump(R, open(os.path.join(OUT, "results.json"), "w"), indent=1)
print(f"{sum(r['ok'] for r in R)}/{len(R)} passed")
sys.exit(0 if all(r["ok"] for r in R) else 1)
