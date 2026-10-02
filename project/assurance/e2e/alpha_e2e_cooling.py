# The cooling-off as testers meet it (REQ-201, REQ-202; CP-030 option A, WI-088), over HTTP against the real server
# with its real 72-hour wait. alpha_e2e.py checks every other workflow on a server without the wait (MIX_ENV=test,
# whose only difference is the wait); this checks what waits, that it says when, that nothing is shown early, that
# it can be withdrawn, and that leaving isn't held up. What happens after the 72 hours is checked by the page and
# contract tests, which move a fixed clock.
# usage: alpha_e2e_cooling.py <port of a fresh household with Ana, Ben, Cy> <out dir>
import sys, os, re, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from browser import Browser, text, msgs
PORT, OUT = int(sys.argv[1]), sys.argv[2]; R = []
def check(w, what, ok, detail=""):
    R.append({"w": w, "check": what, "ok": bool(ok), "detail": detail[:220]}); print(("PASS " if ok else "FAIL ") + w + " | " + what + ((" | " + detail[:220]) if detail else ""))
PW = {"Ana": "ana passphrase 1", "Ben": "ben passphrase 2", "Cy": "cy passphrase 33"}
def unlock(m):
    b = Browser(PORT); b.submit("/", "/login", {"member": m, "passphrase": PW[m]}); return b
def item_id(page, name):
    m = re.search(r'href="/items/([^"]+)"><b>' + re.escape(name), page); return m and m.group(1)
def add(b, note):
    b.submit("/", "/act/add_item", {"note": note, "amount": "100", "frequency": "monthly", "direction": "out"})

ana = unlock("Ana")
add(ana, "Flat rent")
_, home = ana.get("/")
rent = item_id(home, "Flat rent")

# C1 sharing waits, says when, shows nothing early, and can be withdrawn
code, loc, page = ana.submit(f"/items/{rent}", "/act/grant", {"member": "Ben"})
check("C1 sharing", "a share says when it takes effect, 72 hours on", code == 303 and "will be shared with Ben on" in " ".join(msgs(page)), "; ".join(msgs(page)))
check("C1 sharing", "the item page shows it waiting, with when, and Withdraw", "Takes effect on" in text(page) and "Withdraw" in text(page), "")
ben = unlock("Ben"); _, bh = ben.get("/"); c404, _ = ben.get(f"/items/{rent}")
check("C1 sharing", "Ben sees nothing of it yet, even by its address", "Flat rent" not in text(bh) and c404 == 404, f"item page {c404}")
ana = unlock("Ana")
code, loc, page = ana.submit(f"/items/{rent}", "/act/withdraw")
check("C1 sharing", "Ana withdraws it; nothing changed", code == 303 and "Withdrawn. Nothing was changed." in " ".join(msgs(page)), "; ".join(msgs(page)))

# C2 asking someone to own an item: they aren't shown the request during the wait
code, loc, page = ana.submit(f"/items/{rent}", "/act/owners", {"owners[]": ["Ana", "Ben"]}, drop=("owners[]",))
check("C2 owners", "asking Ben to co-own says when he'll see the request", code == 303 and "sees the request on" in " ".join(msgs(page)), "; ".join(msgs(page)))
ben = unlock("Ben"); _, bh = ben.get("/")
check("C2 owners", "Ben isn't shown the request yet", "Waiting for you" not in text(bh) and "Flat rent" not in text(bh), "")

# C3 deleting waits and can be withdrawn
ana = unlock("Ana")
add(ana, "Gym")
_, home = ana.get("/")
gym = item_id(home, "Gym")
code, loc, page = ana.submit(f"/items/{gym}", "/confirm/delete", follow=False)
code, loc, page = ana.submit(f"/items/{gym}", "/act/delete", page=page)
check("C3 deleting", "deleting says when it happens", code == 303 and "will be deleted on" in " ".join(msgs(page)), "; ".join(msgs(page)))
code, gp = ana.get(f"/items/{gym}")
check("C3 deleting", "until then the item is still there, with Withdraw", code == 200 and "Takes effect on" in text(gp) and "Withdraw" in text(gp), str(code))

# C4 leaving isn't held up: a deletion chosen on the leave page happens as the member leaves
cy = unlock("Cy")
add(cy, "Bus pass")
code, loc, page = cy.submit("/leave", "/act/let_go", {"to": "delete"})
check("C4 leaving", "the leave page says the deletion happens when Cy leaves, and offers the leave button", "Deleted when you leave, or on" in text(page) and 'action="/act/leave"' in page, "; ".join(msgs(page)))
code, loc, page = cy.submit("/leave", "/act/leave")
login_page = Browser(PORT).get("/")[1]
check("C4 leaving", "Cy has left at once", code == 303 and ">Cy<" not in login_page, f"{code} {loc}")

json.dump(R, open(os.path.join(OUT, "results-cooling.json"), "w"), indent=1)
print(f"{sum(r['ok'] for r in R)}/{len(R)} passed")
sys.exit(0 if all(r["ok"] for r in R) else 1)
