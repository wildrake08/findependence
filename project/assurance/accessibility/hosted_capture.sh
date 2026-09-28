#!/bin/bash
# usage: hosted_capture.sh <base url, e.g. http://127.0.0.1:4010> <outdir> [path ...]
# Captures pages of the hosted app (hosted/) for axe.sh and screenshots, in light and dark.
# The CSP blocks any injected script, so, like capture.exs, pages are saved as files: the stylesheet is
# inlined and scripts are removed (LiveView's first render is the full page). Dark mode follows the
# device (prefers-color-scheme), so the dark copy rewrites each "@media (prefers-color-scheme:dark)" in
# the built CSS to "@media all", and the light copy to "@media not all". The script checks the built CSS
# uses only that form, and stops otherwise.
set -eu
BASE=$1; OUT=$2; shift 2
PATHS=${*:-/}
mkdir -p "$OUT"
for p in $PATHS; do
  name=$(echo "$p" | sed 's#^/##; s#/#-#g'); name=${name:-home}
  page=$(curl -sSf "$BASE$p")
  css_path=$(echo "$page" | grep -o 'href="/assets/css/[^"]*"' | head -1 | cut -d'"' -f2)
  css=$(curl -sSf "$BASE$css_path")
  forms=$(echo "$css" | grep -o '@media[^{]*prefers-color-scheme[^{]*' | sort -u)
  [ "$forms" = "@media (prefers-color-scheme:dark)" ] || { echo "unexpected media query forms: $forms" >&2; exit 1; }
  for theme in light dark; do
    if [ $theme = dark ]; then repl='@media all'; else repl='@media not all'; fi
    echo "$css" | sed "s/@media (prefers-color-scheme:dark)/$repl/g" > "$OUT/.css"
    echo "$page" | CSS="$OUT/.css" perl -0pe 'BEGIN{local $/; open F,"<",$ENV{CSS}; $c=<F>} s{<link[^>]*rel="stylesheet"[^>]*>}{<style>$c</style>}; s{<script[^>]*>\s*</script>}{}g' > "$OUT/$name-$theme.html"
  done
  rm -f "$OUT/.css"
done
