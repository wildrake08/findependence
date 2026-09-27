# UX-003 verification: measures the rendered geometry its acceptance criteria name, in Chromium.
# usage: geometry.py <width> <file.html>...   (prints one JSON line per page; "fail" lists what's off)
# At any width: controls on one line share height and top; a field's error sits under it; cards have
# equal space above their first and below their last content; a plain list has no rule under its last
# item; checkbox groups share column edges; no sideways scroll. At 1200 px also: numeric headers end
# where their figures end; balances end on one edge; a "Below zero" pill is on its figure's line
# (DEF-034); the header lines up with the cards.
# Needs /usr/bin/chromium and Python 3 (standard library only). Phone widths run inside an iframe,
# because headless Chromium windows are at least 500 px wide.
import sys, os, re, json, html, subprocess, tempfile

JS = r"""
const fail = [], r = e => e.getBoundingClientRect(), near = (a, b, t) => Math.abs(a - b) <= t;
const textBox = e => { const g = document.createRange(); g.selectNodeContents(e); return g.getBoundingClientRect(); };
// a cell's figure: its first non-empty text, outside any "Below zero" pill
const figureBox = td => { const w = document.createTreeWalker(td, NodeFilter.SHOW_TEXT); let n; while ((n = w.nextNode())) if (n.textContent.trim() && !n.parentElement.closest(".below")) { const g = document.createRange(); g.selectNodeContents(n); return g.getBoundingClientRect(); } return null; };
const figureRight = td => { const b = figureBox(td); return b ? b.right : null; };
const wide = innerWidth > 600;
// controls on one visual line: same height, same top
for (const f of document.querySelectorAll("form.row")) {
  const c = [...f.querySelectorAll("input:not([type=hidden]):not([type=checkbox]):not([type=radio]),select,button")].filter(e => e.getClientRects().length);
  for (const a of c) for (const b of c) if (a !== b && r(a).top < r(b).bottom && r(b).top < r(a).bottom) {
    if (!near(r(a).height, r(b).height, 0.5)) fail.push("height " + (a.name || a.textContent.trim()) + " " + r(a).height + " vs " + (b.name || b.textContent.trim()) + " " + r(b).height);
    if (!near(r(a).top, r(b).top, 0.5)) fail.push("top " + (a.name || a.textContent.trim()) + " vs " + (b.name || b.textContent.trim()));
  }
}
// a field's error sits directly under it, on its left edge
for (const e of document.querySelectorAll(".field-error[id]")) {
  const c = document.querySelector("[aria-describedby='" + e.id + "']");
  if (!c) { fail.push("error without field " + e.id); continue; }
  const gap = r(e).top - r(c).bottom;
  if (gap < 0 || gap > 8 || !near(r(e).left, r(c).left, 1)) fail.push("error " + e.id + " gap " + gap.toFixed(1));
}
// cards: space above the first content equals space below the last
for (const k of document.querySelectorAll(".card")) {
  const kids = [...k.children].filter(e => e.getClientRects().length && getComputedStyle(e).position !== "absolute");
  if (!kids.length) continue;
  const cs = getComputedStyle(k), bt = parseFloat(cs.borderTopWidth), bb = parseFloat(cs.borderBottomWidth);
  // an inline form's own box is one text line; the button inside it can be taller, so use its contents too
  // (a closed disclosure's hidden content still has boxes in Chromium, so it's left out)
  const hidden = x => { const d = x.parentElement && x.parentElement.closest("details:not([open])"); return d && !x.closest("summary"); };
  const deep = e => [e, ...e.querySelectorAll("*")].filter(x => x.getClientRects().length && !hidden(x));
  const top = Math.min(...deep(kids[0]).map(x => r(x).top)) - r(k).top - bt;
  const bottom = r(k).bottom - bb - Math.max(...kids.flatMap(deep).map(x => r(x).bottom));
  if (!near(top, bottom, 1)) fail.push("card '" + (k.querySelector("h2")?.textContent || "") + "' " + top.toFixed(1) + " above, " + bottom.toFixed(1) + " below");
}
for (const li of document.querySelectorAll("ul.plain > li:last-child"))
  if (parseFloat(getComputedStyle(li).borderBottomWidth) > 0) fail.push("rule under last list item");
// checkbox groups: at most as many distinct left edges as columns
for (const g of document.querySelectorAll(".checks")) {
  const lefts = new Set([...g.children].map(e => Math.round(r(e).left)));
  const cols = getComputedStyle(g).gridTemplateColumns.split(" ").length;
  if (lefts.size > cols) fail.push("checks: " + lefts.size + " left edges for " + cols + " columns");
}
if (document.documentElement.scrollWidth > innerWidth) fail.push("sideways scroll " + document.documentElement.scrollWidth);
if (wide) {
  // numeric headers end where their column's figures end
  for (const t of document.querySelectorAll("table")) {
    const ths = [...t.querySelectorAll("thead th")];
    ths.forEach((th, i) => {
      if (!th.classList.contains("num")) return;
      const rights = [...t.querySelectorAll("tbody tr")].map(tr => tr.children[i]).filter(td => td && td.classList.contains("num")).map(figureRight).filter(x => x != null);
      if (!rights.length) return;
      const hr = textBox(th).right;
      if (!rights.every(x => near(x, hr, 1))) fail.push("column '" + th.textContent + "' header " + hr.toFixed(1) + " figures " + Math.min(...rights).toFixed(1) + ".." + Math.max(...rights).toFixed(1));
    });
  }
  // WI-047 (DEF-034): a "Below zero" pill sits on its figure's line
  for (const p of document.querySelectorAll("td.num .below")) {
    const f = figureBox(p.closest("td"));
    if (!f) continue;
    const pm = (r(p).top + r(p).bottom) / 2, fm = (f.top + f.bottom) / 2;
    if (!near(pm, fm, 4)) fail.push("pill off its figure's line: " + f.top.toFixed(0) + " vs " + r(p).top.toFixed(0));
  }
  // the header lines up with the cards
  const card = document.querySelector("main .card"), h1 = document.querySelector("header h1"), who = document.querySelector("header form");
  if (card && !near(r(h1).left, r(card).left, 1)) fail.push("header left " + r(h1).left + " card " + r(card).left);
  if (card && who && !near(r(who).right, r(card).right, 1)) fail.push("header right " + r(who).right + " card " + r(card).right);
}
return JSON.stringify({width: innerWidth, fail: fail.slice(0, 12), failures: fail.length});
"""

def run(page, width):
    src = open(page, encoding="utf-8").read()
    inj = "<script>addEventListener('load',()=>{let o;try{o=(function(){" + JS + "})()}catch(e){o=JSON.stringify({error:String(e)})}document.body.setAttribute('data-geometry',o)})</script>"
    d = tempfile.mkdtemp()
    target = os.path.join(d, "page.html")
    open(target, "w", encoding="utf-8").write(src.replace("</body>", inj + "</body>"))
    window = width
    if width < 500:
        outer = os.path.join(d, "frame.html")
        open(outer, "w").write('<!doctype html><body style="margin:0"><iframe id=f src="page.html" style="width:%dpx;height:900px;border:0"></iframe><script>f.onload=()=>setTimeout(()=>document.body.setAttribute("data-geometry",f.contentDocument.body.getAttribute("data-geometry")),300)</script></body>' % width)
        target, window = outer, 600
    out = subprocess.run(["/usr/bin/chromium", "--headless=new", "--no-sandbox", "--disable-gpu", "--hide-scrollbars", "--allow-file-access-from-files",
                          "--window-size=%d,900" % window, "--virtual-time-budget=3000", "--dump-dom", "file://" + target],
                         capture_output=True, text=True).stdout
    m = re.findall(r'data-geometry="([^"]*)"', out)
    return json.loads(html.unescape(m[-1])) if m else {"error": "no result"}

width = int(sys.argv[1])
for page in sys.argv[2:]:
    print(json.dumps({"page": os.path.basename(page), **run(page, width)}))
