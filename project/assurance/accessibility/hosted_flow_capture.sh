#!/bin/bash
# usage: hosted_flow_capture.sh <base url, e.g. http://127.0.0.1:4010> <outdir>
# Captures the hosted app's account and household pages (WI-073; leaving and account deletion, WI-074) for axe.sh, geometry.py, and tabwalk.py, in
# light and dark. Unlike hosted_capture.sh, which only fetches public pages, this goes through the flow a
# member does, with a cookie jar and CSRF tokens: sign up, sign in, start a household, make a code, and so on,
# saving each page, including the refusals. The pages are made into files the same way as hosted_capture.sh:
# the stylesheet inlined, scripts removed, and the dark media query rewritten to "@media all" (dark) or
# "@media not all" (light); both the minified and the development spelling of the query are accepted. Needs a fresh database: the addresses below must be unused.
set -eu
BASE=$1; OUT=$2
mkdir -p "$OUT"
JAR=$(mktemp); JAR2=$(mktemp); trap 'rm -f "$JAR" "$JAR2"' EXIT
PASS="a long passphrase 1"

get() { curl -sS -b "$1" -c "$1" "$BASE$2"; }
token() { echo "$1" | grep -o 'name="_csrf_token"[^>]*value="[^"]*"' | head -1 | sed 's/.*value="//; s/"$//'; }
formtok() { echo "$1" | grep -o 'name="_form"[^>]*value="[^"]*"' | head -1 | sed 's/.*value="//; s/"$//'; }
# post <jar> <page to take the token from> <path> [field=value ...]; prints the response, following a redirect
post() {
  local jar=$1 from=$2 path=$3; shift 3
  local page; page=$(get "$jar" "$from")
  local t; t=$(token "$page")
  local f; f=$(formtok "$page")
  local args=(--data-urlencode "_csrf_token=$t")
  [ -n "$f" ] && args+=(--data-urlencode "_form=$f")
  for f in "$@"; do args+=(--data-urlencode "$f"); done
  curl -sS -L -b "$jar" -c "$jar" "${args[@]}" "$BASE$path"
}

CSS=""
save() {
  local name=$1 page=$2
  if [ -z "$CSS" ]; then
    local css_path; css_path=$(echo "$page" | grep -o 'href="/assets/css/[^"]*"' | head -1 | cut -d'"' -f2)
    CSS=$(curl -sSf "$BASE$css_path")
    # the development build is not minified, so it also writes the query with a space
    local forms; forms=$(echo "$CSS" | grep -o '@media[^{]*prefers-color-scheme[^{]*' | sed 's/ *$//' | sort -u | grep -Ev '^@media \(prefers-color-scheme: ?dark\)$' || true)
    [ -z "$forms" ] || { echo "unexpected media query forms: $forms" >&2; exit 1; }
  fi
  for theme in light dark; do
    if [ $theme = dark ]; then repl='@media all'; else repl='@media not all'; fi
    echo "$CSS" | sed -E "s/@media \(prefers-color-scheme: ?dark\)/$repl/g" > "$OUT/.css"
    echo "$page" | CSS="$OUT/.css" perl -0pe 'BEGIN{local $/; open F,"<",$ENV{CSS}; $c=<F>} s{<link[^>]*rel="stylesheet"[^>]*>}{<style>$c</style>}; s{<script[^>]*>\s*</script>}{}g' > "$OUT/$name-$theme.html"
  done
  rm -f "$OUT/.css"
}

save sign-up "$(get "$JAR" /sign-up)"
save sign-up-refused "$(post "$JAR" /sign-up /sign-up 'account[email]=ana@example.com' "account[passphrase]=short" "account[passphrase_confirmation]=short" 'account[disclosure]=true')"
save recovery-key "$(post "$JAR" /sign-up /sign-up 'account[email]=ana@example.com' "account[passphrase]=$PASS" "account[passphrase_confirmation]=$PASS" 'account[disclosure]=true')"
save sign-in "$(get "$JAR" /sign-in)"
save sign-in-refused "$(post "$JAR" /sign-in /sign-in 'account[email]=ana@example.com' 'account[passphrase]=not the passphrase')"
save recover "$(get "$JAR" /recover)"
save recover-refused "$(post "$JAR" /recover /recover 'account[email]=ana@example.com' 'account[recovery_key]=AAAA-AAAA' "account[passphrase]=$PASS" "account[passphrase_confirmation]=$PASS")"
save household-setup "$(post "$JAR" /sign-in /sign-in 'account[email]=ana@example.com' "account[passphrase]=$PASS")"
save household-join-refused "$(post "$JAR" / /join 'join[code]=AAAA-AAAA-AAAA-AAAA' 'join[display_name]=Ana')"
post "$JAR" / /household 'household[display_name]=Ana Ruiz' > /dev/null
code_page=$(post "$JAR" / /invitations)
save household-new-code "$code_page"
code=$(echo "$code_page" | tr -d '\n' | grep -o 'id="new-code"[^>]*>[^<]*' | sed 's/.*>//; s/ //g')
post "$JAR" / /invitations > /dev/null
save household-home "$(get "$JAR" /)"
save passphrase "$(get "$JAR" /passphrase)"
save passphrase-refused "$(post "$JAR" /passphrase /passphrase "account[current]=$PASS" 'account[passphrase]=short' 'account[passphrase_confirmation]=short')"

# a second member joins with the code
post "$JAR2" /sign-up /sign-up 'account[email]=ben@example.com' "account[passphrase]=$PASS" "account[passphrase_confirmation]=$PASS" 'account[disclosure]=true' > /dev/null
post "$JAR2" /sign-in /sign-in 'account[email]=ben@example.com' "account[passphrase]=$PASS" > /dev/null
save household-joined "$(post "$JAR2" / /join "join[code]=$code" 'join[display_name]=Ben Ruiz')"

# WI-075: the domain pages. Ana adds items (one dated soon), a value, an account and a debt with balances,
# links and shares; each page is saved, with a field mistake, a what-if, a confirmation, and an out-of-date form.
save home-empty "$(get "$JAR" /)"
save add-item-refused "$(post "$JAR" / /act/add_item 'note=Rent' 'amount=12.345' 'direction=out' 'frequency=monthly')"
post "$JAR" / /act/add_item 'note=Rent' 'amount=1,450' 'direction=out' 'frequency=monthly' 'on=2026-10-01' > /dev/null
post "$JAR" / /act/add_item 'note=Pay' 'amount=3,200' 'direction=in' 'frequency=biweekly' 'on=2026-10-03' > /dev/null
post "$JAR" / /act/add_value 'label=Time with the kids' 'return=/' > /dev/null
save balances-new "$(get "$JAR" /balances/new)"
save balances-new-refused "$(post "$JAR" /balances/new /act/add_account 'label=' 'type=checking')"
acct_page=$(post "$JAR" /balances/new /act/add_account 'label=Checking' 'type=checking')
acct=$(echo "$acct_page" | grep -o 'name="item"[^>]*value="[^"]*"' | head -1 | sed 's/.*value="//; s/"$//')
post "$JAR" "/items/$acct" /act/add_reading "item=$acct" 'balance=2,400' 'on=2026-09-28' "return=/items/$acct" > /dev/null
save item-account "$(get "$JAR" "/items/$acct")"
debt_page=$(post "$JAR" /balances/new /act/add_debt 'label=Visa' 'type=card')
debt=$(echo "$debt_page" | grep -o 'name="item"[^>]*value="[^"]*"' | head -1 | sed 's/.*value="//; s/"$//')
save item-debt-refused "$(post "$JAR" "/items/$debt" /act/add_reading "item=$debt" 'balance=6,200' 'on=2026-09-28' 'rate=abc' 'min_payment=150' "return=/items/$debt")"
post "$JAR" "/items/$debt" /act/add_reading "item=$debt" 'balance=6,200' 'on=2026-09-28' 'rate=21.99' 'min_payment=150' "return=/items/$debt" > /dev/null
save item-debt-whatif "$(get "$JAR" "/items/$debt?extra=100&rate=18")"
home=$(get "$JAR" /)
rent=$(echo "$home" | tr -d '\n' | grep -o 'href="/items/[^"]*"[^>]*>[^<]*Rent' | head -1 | sed 's#href="/items/##; s#".*##')
value=$(echo "$home" | tr -d '\n' | grep -o 'href="/items/[^"]*"[^>]*>[^<]*Time with the kids' | head -1 | sed 's#href="/items/##; s#".*##')
ben=$(get "$JAR" "/items/$rent" | grep -o '<option value="[^"]*">Ben Ruiz' | head -1 | sed 's/<option value="//; s/".*//')
post "$JAR" "/items/$rent" /act/link "item=$rent" "value=$value" "return=/items/$rent" > /dev/null
post "$JAR" "/items/$rent" /act/grant "item=$rent" "member=$ben" "return=/items/$rent" > /dev/null
save item-money "$(get "$JAR" "/items/$rent")"
save item-value "$(get "$JAR" "/items/$value")"
save confirm-delete "$(post "$JAR" "/items/$rent" /confirm/delete "item=$rent")"
save home "$(get "$JAR" /)"
save next-60-days "$(get "$JAR" /next-60-days)"
save ahead "$(get "$JAR" /ahead)"
save household-members "$(get "$JAR" /household)"
save item-money-shared-with-ben "$(get "$JAR2" "/items/$rent")"
save not-available "$(get "$JAR" /items/no-such-item)"
stale=$(curl -sS -b "$JAR" -c "$JAR" --data-urlencode '_csrf_token=out-of-date' --data-urlencode '_form=x' --data-urlencode 'label=Late' "$BASE/act/add_value")
save out-of-date "$stale"

# WI-074: Ben leaves, signs in again, and deletes his account (a wrong passphrase first)
save household-leave "$(get "$JAR2" /leave)"
save signed-out-after-leaving "$(post "$JAR2" /leave /leave)"
save household-setup-after-leaving "$(post "$JAR2" /sign-in /sign-in 'account[email]=ben@example.com' "account[passphrase]=$PASS")"
save account-delete "$(get "$JAR2" /account/delete)"
save account-delete-refused "$(post "$JAR2" /account/delete /account/delete 'account[passphrase]=not the passphrase')"
save account-deleted "$(post "$JAR2" /account/delete /account/delete "account[passphrase]=$PASS")"
