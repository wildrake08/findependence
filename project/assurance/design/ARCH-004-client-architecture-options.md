# ARCH-004: client architectures that keep the operator out, on web, desktop, and mobile

**Status:** decided. ACT-001 decided that a web client is essential (REV-110), then chose server-rendered HTML with
progressive enhancement, the server acting as the BFF, and accepted a trusted-operator model (REV-111; CP-024 option
A). The local-first options below are not pursued; the WI-083 spike is withdrawn. See section 6.
**Question:** which architecture meets ASSESS-001's security and privacy findings (above all FND-22: the operator
must not be able to read members' information) and DEF-028's fix (DESIGN-002), runs on web, desktop, and mobile,
and needs the least code?

## 1. What the requirements force

- **The operator can't read data** only if decryption happens on the member's device. Every qualifying option is
  therefore *local-first*: the device holds the keys, decrypts, and applies the household rules; a relay (or the
  household's own cloud folder) stores and forwards only ciphertext and signed operations (DESIGN-002).
- **Web is essential** (REV-110), so the security-critical core (encryption, envelope, household rules, operation
  log, sync) must run *in a browser*. Today's Elixir code can't run in a browser in production (Elixir compiled to
  WebAssembly, AtomVM or Popcorn, is experimental). So either the core is ported once to a language that runs
  everywhere, or it exists twice (Elixir for apps, something else for the web) and must be kept identical.
- **A web client always trusts whoever serves its code.** A static, versioned build with Subresource Integrity,
  signed releases, and an installable app (PWA) narrow this; app stores give desktop and mobile a stronger update
  story. This residual risk is stated, not solved, for the web.
- **Accessibility** is a contract here (axe, Tab walk, forced colours, the accessibility tree): an interface built
  from standard web markup keeps today's tools and results.

## 2. Ranking

Criteria in order of weight: (1) meets the audit (operator excluded; DESIGN-002 feasible; ASSESS-001's controls
carry over; trustworthy code delivery); (2) web, desktop, and mobile from one codebase; (3) fewest implementations
of the security-critical core and least new code; (4) maturity on all three; (5) accessibility.

| # | Solution | Audit | Web / desktop / mobile | Code | Maturity | Accessibility |
|---|---|---|---|---|---|---|
| 1 | **Rust core** (WebAssembly in the browser, native in apps) + **one web-technology interface** in the browser, Tauri desktop, and Tauri mobile | Fully; memory-safe; established crypto libraries | yes / yes / yes (Tauri mobile is the youngest part) | one core, one interface; core ported from Elixir | good web and desktop, moderate mobile | strong (standard markup) |
| 2 | **TypeScript core + one interface**: browser, Tauri or Electron desktop, Capacitor mobile; libsodium or WebCrypto | Fully, with care: npm supply chain, timing side channels in JavaScript | yes / yes / yes | one language for everything; least code | high | strong |
| 3 | **C# throughout**: Blazor WebAssembly web, .NET MAUI desktop and mobile | Fully | yes / yes / yes | one language, two interface layers | high apps, moderate web (large download) | moderate |
| 4 | **React Native + React Native Web**, TypeScript core | Fully | yes / partial (Electron or RN desktop) / yes | one codebase, native crypto modules | high mobile, mixed desktop | good mobile, decent web |
| 5 | **Flutter (Dart)** | Fully | yes / yes / yes | one codebase | high apps | **weaker on web** (canvas rendering) |
| 6 | **Kotlin Multiplatform + Compose Multiplatform** | Fully | beta / yes / yes | shared core, one interface | web immature | uneven |
| 7 | Elixir for desktop and mobile (embedded runtime) + a separate browser client | Fully if both implementations match (shared test vectors) | yes / yes / yes | least new code for apps, **two** security-critical implementations | moderate | strong |
| 8 | Elixir compiled to WebAssembly for the web + embedded Elixir for apps | Fully in principle | yes / yes / yes | one Elixir codebase | **experimental** | strong |
| 9 | Today's server-side hosted form inside confidential-computing hardware, apps as web views | **Partly**: trust moves to hardware and cloud vendors; browsers can't check attestation | yes / yes / yes | least code overall | moderate, complex to run | strong |

Not qualifying: today's hosted form, with or without LiveView Native apps (fails FND-22: the server decrypts);
peer-to-peer only and self-hosting per household as the primary design (the browser needs a signalling server; too
much for study households). Where data syncs (the operator's relay, or the household's own cloud folder) is a
separate choice that works with any option above.

With web essential, options 7 and 8 drop: 7 keeps two security-critical implementations, 8 isn't production-ready.

## 3. Between options 1 and 2

| | Rust core | TypeScript core |
|---|---|---|
| Safety of the security-critical code | memory-safe, strong typing, constant-time crypto crates | relies on libsodium (WASM) or WebCrypto; JavaScript itself can't guarantee constant time |
| Supply chain | Cargo crates, fewer dependencies | npm, typically many dependencies; needs lockfiles, audits, minimal dependencies |
| Code size | core in Rust, interface in TypeScript (two languages) | one language |
| People | narrower hiring pool | widest |
| Performance on phones | near-native | adequate for this app's sizes |
| Port effort | larger | smaller |

Both ports use today's tests and the shared contract suite (shared/test/support/contract) as their specification:
the port must pass the same cases, which makes the move measurable.

## 4. What the spike must show (WI-083)

1. The envelope (sealing, opening, signing, commitments) and one household rule (a grant with consent) ported to
   each candidate, passing the corresponding contract cases from the Elixir suite as test vectors.
2. Interoperability: a record sealed by the port opens in today's Elixir code and the other way round.
3. Performance on a mid-range phone and in a browser: opening a household of 200 and 2,000 items.
4. Packaging: a "hello household" build in the browser, a Tauri desktop app, and a mobile app (Tauri for option
   1, Capacitor for option 2).
5. Accessibility: the same page passes axe and the Tab walk in all three containers.
6. Supply chain: the dependency tree of each, with audit results.

## 5. Not decided here

- Whether the relay is the operator's server or the household's own cloud folder (or both).
- The relay and sync design (joining, adding a device, fingerprints): a design note after the spike, for the same
  independent review as DESIGN-002.
- What happens to today's hosted form (likely replaced by the relay) and to the local form (likely replaced by the
  new client once it passes the same gates).


## 6. Decision (REV-111)

**Chosen:** server-rendered HTML with progressive enhancement, the web server acting as the BFF: the hosted form as
built (Phoenix templates; every form works without JavaScript; the session is an HttpOnly cookie holding a random
token, with keys only in server memory; no tokens in the browser). The operator is trusted while members are signed
in, as REQ-180 discloses; ASSESS-001 FND-22 is an accepted risk.

**Why it fits:** the smallest cross-site-scripting surface (almost no script, no data in the browser), the
accessibility contract already met, strong CSRF and session controls, and the least code (it exists).

**What follows:**

- Desktop and mobile use the same pages, as an installable web app or app-store wrappers around a web view;
  online only.
- With a trusted operator, protection rests on operating controls; before the hosted form's first release:
  no production console by default (release distribution off, or a console only under a two-person procedure),
  audited operator access (WI-077, in place), memory not swapped and no core dumps, the database roles and TLS of
  WI-081, and an independent audit of operator access. To be scoped in the deploying WorkItem.
- GATE-016's professional check (whether US or Washington financial-privacy rules apply to a service whose
  operator can read members' finances while they're signed in) is the decision this now depends on most.
- DESIGN-002 (DEF-028) is still needed for the local form, whose household members share an editable file. In the
  hosted form the server is the authority, so members can't tamper with the shared state; the operator can.
