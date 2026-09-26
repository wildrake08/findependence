#!/bin/bash
# usage: [KIND=incomplete] axe.sh <dir of captured .html> <outdir>
# Runs axe-core at 1200 px (window) and 390 px (iframe). KIND=violations (default) or incomplete ("needs review").
KIND=${KIND:-violations}
IN=$1; OUT=$2; A=$(dirname $0)/axe.min.js; mkdir -p $OUT
C="/usr/bin/chromium --headless=new --no-sandbox --disable-gpu --allow-file-access-from-files --virtual-time-budget=10000"
RUN0='<script src="file://AXE"></script><script>axe.run(document,{resultTypes:["KIND"]}).then(r=>{const v=r["KIND"].map(x=>({id:x.id,impact:x.impact,help:x.help,n:x.nodes.length,t:x.nodes.slice(0,3).map(n=>n.target.join(" "))}));const s=JSON.stringify(v);if(window.parent!==window){window.parent.document.getElementById("out").textContent=s}else{document.getElementById("axe-out").textContent=s}}).catch(e=>{(window.parent!==window?window.parent.document.getElementById("out"):document.getElementById("axe-out")).textContent="ERR "+e})</script>'
RUN=${RUN0//KIND/$KIND}
for f in $IN/*.html; do n=$(basename $f .html)
  sed "s#</body>#<pre id=axe-out hidden></pre>${RUN//AXE/$A}</body>#" $f > $OUT/$n.axe.html
  $C --window-size=1200,900 --dump-dom file://$OUT/$n.axe.html 2>/dev/null | grep -o '<pre id="axe-out"[^>]*>[^<]*' | sed 's/<pre[^>]*>//' > $OUT/$n.1200.json
  echo "<html><body><pre id=out></pre><iframe src=\"file://$OUT/$n.axe.html\" style=\"width:390px;height:900px\"></iframe></body></html>" > $OUT/$n.phone.html
  $C --window-size=600,900 --dump-dom file://$OUT/$n.phone.html 2>/dev/null | grep -o '<pre id="out">[^<]*' | sed 's/<pre[^>]*>//' > $OUT/$n.390.json
done
