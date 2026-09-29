# WI-066: compares two directories of captured pages (from capture*.exs) for a no-change refactoring.
# usage: pagecompare.py <before dir> <after dir>   (exit 1 if any comparable page differs)
import re,sys,os
# WI-066 page comparison: per-request tokens and random IDs (new_id: 12 url-safe base64 chars) are
# replaced by placeholders, each ID by its order of first appearance; everything else must match exactly.
ID=re.compile(r'(?:/items/|/plans/|/requests/|value="|value=|to-|contribution_)([A-Za-z0-9_-]{12})(?![A-Za-z0-9_-])')
def norm(s):
    s=re.sub(r'name=_csrf_token value="[^"]*"','name=_csrf_token value="T"',s)
    s=re.sub(r'name=_form value="[^"]*"','name=_form value="F"',s)
    ids=[]
    for m in ID.finditer(s):
        if m.group(1) not in ids: ids.append(m.group(1))
    for n,i in enumerate(ids):
        s=re.sub(r'(?<![A-Za-z0-9])'+re.escape(i)+r'(?![A-Za-z0-9_])','ID%d'%n,s)
    return s
# v5-item-brought shows whichever brought-in item the capture script finds first by random ID
EXCLUDED={'v5-item-brought.html'}
a,b=sys.argv[1],sys.argv[2]; diffs=[]; n=0
for f in sorted(os.listdir(a)):
    if not f.endswith('.html') or f in EXCLUDED: continue
    n+=1
    if norm(open(os.path.join(a,f)).read())!=norm(open(os.path.join(b,f)).read()): diffs.append(f)
print(f"{n} pages; {len(diffs)} differ after normalization: {diffs}")
sys.exit(1 if diffs else 0)
