# FEAS-001: Phoenix and Petal Components with no JavaScript (WI-061)

Status: **stopped at part 2** under WI-061's stop rule (REQ-124 AC-1 cannot hold). Part 3 (the unlock page)
was not started. No app code was changed; the dependency trial was reverted.

Produced by ACT-002 under REV-074, 2026-09-28. Inputs: CP-017, REV-072, `requirements-prototype.yaml`,
petal_components 4.16.1 (Hex, unpacked and read), Tailwind v4.3.3 (GitHub release).

## Part 1: components (done)

Petal 4.16.1 runs with no script for everything this interface uses, with two exceptions noted below.
Read from each component's source: a component needs script only where it has `phx-hook`, `JS.` commands,
or `phx-*` event bindings.

| Needed for | Petal component | No script? | Note |
|---|---|---|---|
| buttons, links | `button`, `link` | yes | `link` drops `phx-click` itself |
| forms: text, password, date, file, select, radio group, hidden | `form`, `field`, `input` | yes | hooks only for opt-in `viewable` password, `copyable`, `clearable`, and range sliders; don't use them |
| checkboxes | `field type="checkbox"` | **partly** | the tick on `.pc-checkbox:checked` is a `data:` SVG; `default-src 'none'` blocks it, so a checked box shows only its colour (colour as the sole signal, WCAG 1.4.1). Use a native checkbox |
| tables | `table` | yes | without `on_sort` or `row_click` |
| cards, headings, text, badges, separators, icons, empty states | `card`, `typography`, `badge`, `separator`, `icon`, `empty`, `container` | yes | |
| notices | `alert` | yes | without dismiss commands. But existing tests pin today's notice markup (`<p class="msg info" role="status">`), so moving to `alert` means re-targeting those tests |
| disclosure (today `<details>`) | `accordion`, `collapsible` | **no** | both use `JS`; keep native `<details>` |

Not usable at all: modals, dropdowns, popovers, toasts, tabs, combobox, date picker; none is needed today.

## Part 2: dependencies and Tailwind (stopped)

**Dependencies.** Adding phoenix ~> 1.8, phoenix_live_view ~> 1.1, phoenix_html ~> 4.1 and
petal_components ~> 4.16 locks 12 new packages beside today's 8: decimal 3.1.1, ecto 3.14.2, jason 1.4.5,
petal_components 4.16.1, phoenix 1.8.15, phoenix_ecto 4.7.0, phoenix_html 4.3.0, phoenix_html_helpers
1.0.1, phoenix_live_view 1.2.12, phoenix_pubsub 2.3.0, phoenix_template 1.1.0, websock_adapter 0.5.9.
Petal requires LiveView and phoenix_ecto (so Ecto) even when neither is used; option B would use LiveView
only for `Phoenix.Component` rendering.

**REQ-124 AC-1 fails (DEF-054).** Every dependency's source was scanned for `:httpc`, `:gen_tcp.connect`,
`:ssl.connect`, `:inet` lookups, Mint, Finch, Req, HTTPoison, Tesla and hackney. One real call:
`phoenix/lib/mix/tasks/phx.gen.release.ex:497`, `:httpc.request`, in a developer Mix task that looks up
Docker image tags. The served app never calls it, but AC-1 says the dependencies must not contain one.
Every phoenix release Petal accepts ships it. The other matches (plug, thousand_island) are type specs
naming `:ssl.connection_info`, present before this work.

**The existing test would not have caught it (DEF-055).** AC-1's test reads the app's source and the
names of direct dependencies, not their source.

**Tailwind.** The Tailwind v4.3.3 standalone binary is 110 MB (linux-arm64, sha256
`55fd0b24…398195`, matching the release's list). GitHub refuses files over 100 MB, so it can't be committed
as-is. The alternative that keeps AC-1 is to pin its version and checksum in the repository, fetch it once
outside Mix, and commit the built CSS; the Tailwind Hex package must not be used, because it downloads with
`:httpc`. Not built yet.

**CSS size and the CSP (not yet measured).** Petal's stylesheet source is 470 KB. The CSP allows only
inline styles (`style-src 'unsafe-inline'`), so the built CSS must go in each page's `<style>`, as today;
its built size decides whether that is acceptable.

## Part 3: the unlock page (not started)

Found while preparing it:

- The Phoenix pieces would run behind today's Plug pipeline (Host check, headers, session, CSRF, one-time
  forms), not in a separate `Phoenix.Endpoint` that re-implements them; moving the pipeline is the full
  rebuild's work.
- Nearly every web test reads the CSRF token from the unlock page with `name=_csrf_token value="…"`
  (unquoted), so the existing `csrf()` output would be embedded unchanged.

## Decision needed (ACT-001)

1. **Restate AC-1** to what the running system can call: no HTTP client or connect call reachable from
   the app's processes or request handling, and none in any dependency's runtime code, with developer-only
   Mix tasks excluded and listed. WI-061 then resumes at part 2 (Tailwind build, CSS size) and part 3.
2. **Keep AC-1 as written**: CP-017 B is not possible with Petal; fall back to CP-017 option C (keep Plug,
   apply the same quality standards to today's pages).

ACT-002 recommends 1 if the rebuild is still wanted. AC-1 protects against the app contacting anything,
and a Mix task that the served app never loads doesn't do that. The restatement should be narrow and
checked by a test that scans dependency sources (DEF-055), so the exclusion is visible rather than silent.
Choose 2 if "nothing that can make a network call is installed" matters in itself, for example to a
reviewer.
