# UX-005 (WI-051) and WI-062: in forced colours, fills and shadows are dropped, so every state must keep a border.
# usage: [THEME=dark] forced.py <file.html>...   (prints one JSON line per page; "fail" lists what's off)
# Checks, with Chromium's forced colours on (computed styles): every button, field, and button link has a border;
# .msg, .below, and .badge have one; an invalid field's border is wider than a valid one's; attention and warn
# cards' borders are wider than a plain card's; a solid button's is wider than an outline button's.
# Rules as recorded in UI-RUN-008. THEME=dark also sets prefers-color-scheme: dark.
# Needs /usr/bin/chromium and Python 3 (standard library only).
import sys, os, re, json, html, subprocess, tempfile

JS = r"""
const w = e => { const s = getComputedStyle(e); return s.borderTopStyle === 'none' ? 0 : parseFloat(s.borderTopWidth) };
const name = e => e.tagName.toLowerCase() + (e.className ? '.' + String(e.className).trim().replace(/\s+/g, '.') : '') + (e.name ? '[' + e.name + ']' : '');
const shown = e => e.getClientRects().length > 0;
const fail = [];
const all = sel => [...document.querySelectorAll(sel)].filter(shown);
if (!matchMedia('(forced-colors:active)').matches) fail.push('forced colours not active');
for (const e of all('button,a.button-link,input:not([type=hidden]):not([type=checkbox]):not([type=radio]),select,.msg,.below,.badge'))
  if (w(e) < 1) fail.push('no border: ' + name(e));
const valid = all('input:not([aria-invalid=true]):not([type=hidden]):not([type=checkbox]):not([type=radio]),select:not([aria-invalid=true])').map(w);
for (const e of all('input[aria-invalid=true],select[aria-invalid=true]'))
  if (valid.length && w(e) <= Math.max(...valid)) fail.push('invalid not wider: ' + name(e));
const plain = all('.card:not(.attention):not(.warn)').map(w);
for (const e of all('.card.attention,.card.warn'))
  if (w(e) <= Math.max(1, ...plain)) fail.push('state card not wider: ' + name(e));
const outline = all('.inline button:not(.primary),td button').map(w);
for (const e of all('button')) {
  const solid = !e.closest('.inline,td') || e.classList.contains('primary');
  const danger = e.classList.contains('danger') && !e.closest('.card.warn');
  if (solid && !danger && outline.length && w(e) <= Math.max(...outline)) fail.push('solid not wider than outline: ' + name(e));
}
const counts = {controls: all('button,a.button-link,input,select').length, states: all('.msg,.below,.badge,.card.attention,.card.warn,[aria-invalid=true]').length};
return JSON.stringify({...counts, fail: [...new Set(fail)]});
"""

def run(page):
    src = open(page, encoding="utf-8").read()
    inj = "<script>addEventListener('load',()=>{let o;try{o=(function(){" + JS + "})()}catch(e){o=JSON.stringify({error:String(e)})}document.body.setAttribute('data-forced',o)})</script>"
    d = tempfile.mkdtemp()
    target = os.path.join(d, "page.html")
    open(target, "w", encoding="utf-8").write(src.replace("</body>", inj + "</body>"))
    out = subprocess.run(["/usr/bin/chromium", "--headless=new", "--no-sandbox", "--disable-gpu", "--force-high-contrast",
                          "--window-size=1200,900", "--virtual-time-budget=3000", "--dump-dom", "file://" + target]
                         + (["--force-dark-mode"] if os.environ.get("THEME") == "dark" else []),
                         capture_output=True, text=True).stdout
    m = re.findall(r'data-forced="([^"]*)"', out)
    return json.loads(html.unescape(m[-1])) if m else {"error": "no result"}

for page in sys.argv[1:]:
    print(json.dumps({"page": os.path.basename(page), **run(page)}))
