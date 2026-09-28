<!--
ARCH-001: reference architecture for the hosted edition of Findependence.
Source: pasted by ACT-001 in session, 2026-09-28. Recorded by ACT-002 (REV-078, CHG-075).
Status: adopted by ACT-001 as the target architecture for the hosted edition (REV-078, CP-019), with the
open decisions listed in CP-019. It does not govern the local-first interface (IE-205), which stays under
CP-017 option C (REV-075) and WI-062.
The text below is ACT-001's, unedited. How it maps onto this project (tenant = household, principal = member,
the per-member encryption it does not cover, REQ-124) is recorded in CP-019 and DEF-056, not here.
-->

# Normalized Secure Reference Architecture

## Elixir 1.20.4 · Phoenix 1.8.x · LiveView 1.2.x · Petal Components 4.16.x

## 0. Scope and normative model

This specification defines the production architecture for a secure, SaaS-capable Phoenix application using:

- Elixir 1.20.4;
- a supported Erlang/OTP release;
- Phoenix 1.8.x;
- Phoenix LiveView 1.2.x;
- Petal Components 4.16.x;
- HEEx;
- Tailwind CSS 4.x;
- Ecto;
- PostgreSQL unless another datastore is explicitly justified;
- Bandit or another explicitly supported Phoenix HTTP adapter;
- minimal client-side JavaScript.

For the Petal 4.16 line, `4.16.1` is the preferred baseline unless an explicit constraint requires another 4.16.x patch.

This specification is intentionally divided into:

1. normative architectural requirements;
2. conditional requirements activated by used capabilities;
3. objective assurance evidence.

A requirement SHALL appear in one canonical normative location. Other sections SHALL reference rather than redefine it.

### Normative terms

- **SHALL / MUST** — required for architectural conformance.
- **SHALL NOT / MUST NOT** — prohibited.
- **SHOULD** — default unless a documented reason justifies deviation.
- **MAY** — optional.

Security, privacy, transactional correctness, accessibility, and truthful system behavior override implementation convenience or visual preference.

### Architectural invariant

The system SHALL preserve this separation:

```text
Experience architecture
        ↓
Application design system
        ↓
Petal Components
        ↓
Phoenix LiveView
        ↓
Phoenix web infrastructure

independently:

Authenticated principal
        ↓
Tenant / resource boundary
        ↓
Authorization
        ↓
Application/domain operation
        ↓
Ecto
        ↓
Persistent storage
```

The presentation path and authority path meet only through controlled application operations.

The browser SHALL never be a source of authority.

---

# 1. Version and compatibility contract

## 1.1 Runtime baseline

The approved baseline is:

```text
Elixir                1.20.4
Erlang/OTP            explicitly pinned supported release
Phoenix               patched 1.8.x release
Phoenix LiveView      patched 1.2.x release
Petal Components      4.16.x
Tailwind CSS          4.x
```

The deployment environment SHALL pin the actual Elixir and OTP versions.

All production replicas SHALL use the same approved runtime family.

## 1.2 Dependency policy

Petal Components SHALL remain inside the approved 4.16 line.

A representative dependency policy is:

```elixir
def project do
  [
    elixir: "~> 1.20.4",
    ...
  ]
end

defp deps do
  [
    {:phoenix, "~> 1.8"},
    {:phoenix_live_view, "~> 1.2"},
    {:petal_components, "~> 4.16.1"},
    {:phoenix_ecto, "~> 4.4"},
    {:ecto_sql, "~> 3.0"},
    {:phoenix_html, "~> 4.1"},
    {:bandit, "~> 1.0"}
  ]
end
```

The exact production graph SHALL be determined by the committed `mix.lock`.

`mix.lock` SHALL:

- be committed;
- be reviewed when dependencies change;
- be used for CI and release builds;
- not be regenerated opportunistically in production.

## 1.3 Security patch policy

Compatibility constraints SHALL NOT be treated as security guarantees.

Phoenix, LiveView, Petal, Elixir, OTP, database drivers, HTTP clients, asset dependencies, and other security-relevant packages SHALL remain on supported patched releases compatible with this architecture.

A known exploitable vulnerability overrides a preference to remain on an older patch version.

## 1.4 Petal version authority

For Petal APIs, authority SHALL be:

```text
1. installed Petal 4.16.x package source
2. installed-version HexDocs/package documentation
3. Petal MCP output confirmed to represent the installed version
4. official documentation matching the installed release
5. examples or remembered APIs only after verification
```

An implementation SHALL NOT guess:

- component names;
- attrs;
- slots;
- hook names;
- class contracts;
- installation paths;
- supported values.

Current documentation from a later Petal release SHALL NOT silently redefine the installed 4.16.x API.

## 1.5 Installation-path rule

Filesystem paths, import paths, CSS source directives, and hook import paths SHALL be taken from the installed Petal 4.16.x package instructions and adapted to the actual repository layout.

Specific path spellings SHALL NOT be treated as architectural invariants.

The assurance condition is that:

- assets compile;
- Petal styles are present;
- Petal hooks load;
- no required package resources are omitted.

---

# 2. Architectural responsibility model

Each layer SHALL have one primary responsibility.

| Layer | Owns |
|---|---|
| Experience architecture | Quality criteria and task appropriateness |
| Application design system | Product visual/interaction language |
| Petal Components | Generic UI primitives |
| Product components | Reusable domain-facing UI compositions |
| LiveView | Interactive presentation state and event orchestration |
| Phoenix | HTTP, routing, sessions, endpoint infrastructure |
| Application contexts | Use cases and business behavior |
| Authorization | Whether an operation is permitted |
| Tenancy | Resource boundary and ownership scope |
| Ecto | Persistence operations and data constraints |
| PostgreSQL | Durable state and enforceable invariants |
| OTP | Supervision and runtime resilience |
| Deployment infrastructure | Secure execution, networking, secrets, storage |

## 2.1 Dependency direction

Dependencies SHALL flow toward domain/data boundaries:

```text
Petal Components
        ↑
Product components
        ↑
LiveViews / controllers
        ↓
Application contexts
        ↓
Policies / domain modules
        ↓
Ecto / integrations
```

Domain modules SHALL NOT depend on:

- Phoenix;
- LiveView;
- HEEx;
- Petal;
- CSS;
- DOM concepts;
- browser JavaScript.

Petal components SHALL NOT perform database access.

## 2.2 Source topology

A conventional single Phoenix application SHOULD be preferred unless independent deployment, ownership, scaling, or failure isolation justifies an umbrella.

A representative structure is:

```text
lib/
├── my_app/
│   ├── accounts/
│   ├── organizations/
│   ├── projects/
│   ├── billing/
│   ├── policies/
│   ├── integrations/
│   ├── audit/
│   ├── workers/
│   └── repo.ex
│
└── my_app_web/
    ├── auth/
    ├── components/
    │   ├── layouts/
    │   ├── product/
    │   └── design/
    ├── controllers/
    └── live/
```

Contexts SHALL represent meaningful domain boundaries rather than generic service directories.

---

# 3. Trust and authority contract

This section is the canonical security authority model.

## 3.1 Fundamental trust rule

All client-originated data SHALL be treated as untrusted.

This includes:

- URL parameters;
- query strings;
- form data;
- `phx-value-*`;
- hidden inputs;
- LiveView event payloads;
- cookies before verification;
- upload metadata;
- request headers;
- browser-generated IDs;
- client-selected tenant IDs;
- client-visible entitlement state.

Presentation state SHALL never grant authority.

Therefore:

```text
hidden control     ≠ authorization
disabled control   ≠ authorization
missing navigation ≠ authorization
modal confirmation ≠ authorization
Petal variant      ≠ authorization
client-side role   ≠ authorization
```

## 3.2 Authentication

Authentication SHALL establish an authoritative server-side principal.

Protected LiveViews SHALL verify authenticated state through the HTTP and connected LiveView lifecycle.

`live_session` and `on_mount` SHOULD be used to enforce route-level authentication where appropriate.

Session cookies SHALL contain minimal identity/session material rather than complete domain objects.

Security-sensitive account-state changes SHOULD invalidate or refresh affected sessions as warranted by the threat model.

## 3.3 Authorization

Every consequential operation SHALL authorize:

```text
actor
+
action
+
resource
+
tenant
+
current resource state
```

when those dimensions are applicable.

Authorization SHALL occur server-side.

Security-sensitive contexts callable from multiple entry points SHOULD enforce authorization at the domain boundary even when LiveView has already performed an earlier check.

## 3.4 Tenancy

Tenant scope SHALL come from trusted server state.

A client-provided organization/account identifier SHALL NOT determine tenant authority without server-side validation.

Tenant-aware data access SHOULD follow:

```text
authenticated actor
        ↓
authorized tenant
        ↓
tenant-scoped base query
        ↓
resource operation
```

rather than:

```text
client resource ID
        ↓
global lookup
        ↓
authorization afterward
```

Critical tenant relations SHOULD also be protected through database constraints where practicable.

## 3.5 Entitlements

Subscription plans, quotas, feature flags, roles, contracts, and product entitlements SHALL be verified server-side before protected operations.

Client-visible entitlement state MAY improve presentation but SHALL NOT constitute entitlement authority.

## 3.6 Canonical mutation contract

All consequential state-changing LiveView operations SHALL reduce to:

```text
client event
        ↓
event-shape validation
        ↓
server-owned actor / tenant
        ↓
application operation
        ↓
authorization
        ↓
domain validation
        ↓
transaction / durable mutation
        ↓
secondary effects
        ↓
authoritative result
        ↓
presentation update
```

A successful presentation state SHALL NOT precede authoritative success for security-, billing-, or transaction-critical operations.

## 3.7 Input safety

Changesets and other parsers SHALL explicitly control accepted fields.

The application SHALL NOT:

- dynamically atomize arbitrary user strings;
- concatenate untrusted input into SQL;
- evaluate user-controlled code or Elixir terms;
- deserialize unsafe native terms from untrusted sources;
- mass-assign unrestricted external maps.

## 3.8 Output safety

HEEx escaping SHALL remain the default.

Untrusted content SHALL NOT be rendered through `raw/1` or equivalent bypasses without an explicit sanitization contract.

User-controlled URLs SHALL be validated for permitted schemes and intended destinations where they affect navigation, embedded resources, or security-sensitive behavior.

---

# 4. Petal design-system contract

Petal Components SHALL provide generic implementation primitives beneath the application-owned design system.

## 4.1 Ownership model

The application design system owns:

- product experience principles;
- semantic tokens;
- brand;
- typography;
- density;
- navigation conventions;
- information hierarchy;
- accessibility requirements;
- domain-specific interaction patterns;
- error/recovery patterns;
- reusable product compositions.

Petal owns generic primitives such as:

- controls;
- forms;
- inputs;
- typography;
- cards;
- overlays;
- menus;
- navigation;
- tables;
- feedback;
- date/calendar controls;
- command surfaces;
- data display;
- other supported primitives.

## 4.2 Prefer Petal primitives

When a materially equivalent Petal component exists, it SHOULD be used rather than rebuilding the same primitive with raw HEEx and Tailwind.

Raw HEEx remains appropriate for:

- page structure;
- product-specific composition;
- semantic layout;
- structures Petal does not represent.

Do not create a parallel generic component library.

## 4.3 Product-component extraction

An application-owned component SHOULD be created when it:

- represents a domain concept;
- occurs repeatedly;
- encodes stable behavior;
- enforces meaningful semantic consistency;
- materially improves correctness or maintainability.

Appropriate:

```text
<ProjectSummary />
<OrganizationSwitcher />
<SubscriptionStatus />
<UsageMeter />
<PermissionMatrix />
```

Usually unnecessary:

```text
<MyButton />
<MyCard />
<MyModal />
```

unless they define a deliberate product-wide contract beyond Petal.

## 4.4 CoreComponents coexistence

Petal SHALL own generic primitives unless a deliberate exception exists.

Generated Phoenix CoreComponents MAY retain application-specific helpers.

The application SHOULD avoid two competing implementations of generic controls such as:

- inputs;
- buttons;
- modals;
- tables;
- flashes;
- form fields.

## 4.5 Token architecture

Custom markup SHALL share the same semantic token system as Petal.

At minimum govern:

```text
primary
secondary
gray
success
warning
danger
info
radius
heading typography
body typography
monospace typography
```

Arbitrary per-page color systems SHOULD NOT be introduced.

Color SHALL NOT be the sole carrier of meaning.

## 4.6 Radius

The application's global component-radius policy SHOULD use Petal's supported radius token rather than unrelated per-component values.

Exceptions SHALL be deliberate.

## 4.7 Typography

Petal 4.16's heading/body/mono typography-token model SHOULD be used when the application requires differentiated semantic font families.

Typography SHALL preserve:

- semantic heading structure;
- readable line length;
- predictable hierarchy;
- accessible contrast;
- stable vertical rhythm.

## 4.8 Light and dark modes

Light and dark modes SHALL be two expressions of one semantic system.

Both SHALL preserve:

- hierarchy;
- state meaning;
- accessibility;
- affordance;
- visual emphasis.

Dark mode SHALL NOT be implemented as arbitrary class inversion.

## 4.9 CSS extension priority

Use this order:

```text
1. Petal component API
2. Petal semantic tokens
3. application semantic tokens
4. layout utilities
5. narrowly scoped custom CSS
6. arbitrary values only when justified
```

Avoid:

- deep dependence on undocumented internal DOM;
- widespread `!important`;
- arbitrary shadows/radii/colors;
- reimplementation of supported interactive states.

## 4.10 Tailwind integration

The project SHALL use the installed Petal 4.16.x Tailwind integration instructions appropriate to its layout.

The resulting build SHALL:

- scan required Petal source;
- include Petal default styles;
- include application theme overrides after Petal defaults where required;
- exclude unnecessary showcase/demo sources where supported and desirable;
- successfully compile production assets.

---

# 5. LiveView interaction and state contract

## 5.1 State ownership

State SHALL have one authoritative owner:

```text
durable domain state
    → database / durable infrastructure

business workflow state
    → application contexts

authenticated identity
    → verified server session

interactive page state
    → LiveView assigns

large mutable rendered collections
    → LiveView streams where appropriate

ephemeral browser-only behavior
    → LiveView.JS or narrow hooks
```

The browser SHALL NOT independently own authoritative business state.

## 5.2 Lifecycle

`mount/3` SHOULD establish:

- principal;
- tenant/context;
- route eligibility;
- minimal initial state;
- authorized subscriptions.

`handle_params/3` SHALL treat parameters as untrusted.

`handle_event/3` SHALL follow the canonical mutation contract where state changes occur.

`handle_info/2` SHALL process only understood messages.

## 5.3 JavaScript

Phoenix.LiveView.JS and Petal's bundled hooks SHALL be preferred over introducing another frontend state runtime.

Application hooks SHALL remain narrowly scoped to browser-local behavior that cannot reasonably be represented through server state or LiveView.JS.

Hooks SHALL NOT contain:

- secrets;
- permission logic;
- authoritative entitlements;
- persistent business state.

React, Vue, Alpine, or another state framework SHOULD NOT be introduced for ordinary LiveView interactions.

## 5.4 Forms

Forms SHOULD use:

```text
Phoenix.Component.to_form/2
+
changesets where domain-appropriate
+
Petal form primitives
```

Validation SHALL occur server-side even when browser validation is present.

Recoverable failures SHOULD preserve valid user input.

## 5.5 Collections

Large collections SHOULD use:

- database pagination;
- LiveView streams;
- controlled incremental loading;

rather than unlimited assigns.

Filtering and sorting exposed through UI components SHALL be mapped to explicit allowlisted server-side query operations.

## 5.6 Navigation and commands

Menus, sidebars, command palettes, breadcrumbs, tabs, and other navigation MAY omit unavailable actions for usability.

Their visibility SHALL NOT constitute authorization.

Privileged commands SHALL invoke the same authorized domain operations as any other entry point.

## 5.7 Realtime behavior

PubSub and Presence SHALL be treated as transport/state-distribution facilities rather than authority systems.

Subscriptions SHALL occur only after authorization.

Reconnect-sensitive security state SHOULD be refreshed from authoritative server sources when necessary.

---

# 6. Domain and data contract

## 6.1 Context ownership

Application contexts SHALL own business use cases.

LiveViews SHOULD invoke public context operations rather than arbitrary repository calls.

## 6.2 Data invariants

Appropriate invariants SHALL be enforced as close as practical to the durable data boundary through:

- foreign keys;
- unique constraints;
- check constraints;
- transaction boundaries;
- optimistic locking where appropriate.

Application validation does not replace database integrity.

## 6.3 Transactions

Operations requiring atomicity SHALL use an Ecto transaction or equivalent.

External irreversible side effects SHOULD NOT occur inside database transactions unless the external system explicitly supports compatible transactional semantics.

Where appropriate:

```text
commit durable application state
        ↓
enqueue durable side effect
        ↓
background worker performs integration
```

## 6.4 External integrations

External services SHALL be wrapped behind application-owned adapters responsible for:

- credentials;
- request construction;
- timeout;
- bounded retries;
- idempotency behavior;
- response validation;
- normalization;
- error classification;
- telemetry;
- redaction.

Vendor response structures SHOULD NOT leak throughout the domain.

## 6.5 Background work

Long-running or retryable work SHOULD leave the LiveView process.

Examples include:

- email;
- exports;
- billing synchronization;
- media processing;
- AI calls;
- webhook retries;
- bulk imports;
- report generation.

Retryable jobs SHALL be idempotent where duplicate execution is possible.

## 6.6 Caching

Every cache SHALL define:

- scope;
- key;
- tenant/user isolation;
- TTL where applicable;
- invalidation;
- failure behavior.

Protected cached data SHALL NOT cross authorization or tenant boundaries.

---

# 7. Conditional capability contracts

The following sections activate only when the application uses the corresponding capability.

Unused capabilities SHALL NOT create unnecessary dependencies or architecture.

## 7.1 User-generated rich text / Markdown

If rich text or Markdown is accepted:

- define permitted markup;
- distinguish rendering from sanitization;
- sanitize hostile HTML where HTML is accepted;
- validate URLs and media;
- define external-resource/privacy policy;
- prohibit unsafe raw rendering.

## 7.2 File uploads

If uploads exist, define:

- size limit;
- count limit;
- accepted content classes;
- content-validation policy;
- authorization;
- storage location;
- retention;
- processing;
- malware inspection where threat-appropriate.

Treat filename, extension, MIME type, and metadata as untrusted.

Use server-generated storage identifiers.

## 7.3 OTP / verification codes

If OTP-style authentication or verification exists, implement:

- secure generation;
- expiration;
- one-time consumption;
- attempt limits;
- generation rate limits;
- replay protection;
- principal/action binding.

The Petal OTP input is presentation only.

## 7.4 Billing

If billing exists:

- normalize provider state into domain-owned billing/entitlement state;
- verify provider webhooks;
- make webhook handling idempotent;
- never trust browser-posted plan or price authority;
- authorize product capabilities from server-owned entitlement state.

## 7.5 Webhooks

If webhooks exist:

1. verify authentication/signature;
2. enforce replay/idempotency behavior;
3. normalize event data;
4. invoke domain operations;
5. return the expected provider response.

## 7.6 Charts

If Petal charts requiring a browser charting engine are used:

- pin the approved charting dependency;
- prefer bundled application assets over ungoverned runtime CDN dependencies;
- include the dependency in CSP and supply-chain review;
- treat user-controlled labels/tooltips as untrusted.

## 7.7 QR codes

If QR codes encode privileged actions or secrets:

- use short-lived tokens where practical;
- scope tokens to their intended operation;
- validate embedded destinations;
- assume the QR contents are visible to anyone who can scan them.

## 7.8 User-influenced outbound requests

If users can influence URLs fetched by the server, the application SHALL define SSRF controls.

At minimum consider:

- allowed protocols;
- destination allowlists where appropriate;
- DNS/IP resolution policy;
- loopback/private/link-local restrictions;
- redirect policy;
- request timeout;
- response-size limit;
- egress policy.

## 7.9 Browser APIs / CORS

If cross-origin browser APIs exist:

- define allowed origins explicitly;
- distinguish credentialed from non-credentialed access;
- do not use wildcard credentialed CORS;
- authenticate APIs independently of CORS;
- define CSRF behavior according to credential model.

## 7.10 Persistent customer data lifecycle

If customer data is persisted, define:

- retention;
- deletion;
- backup;
- restore;
- disaster-recovery expectations;
- tenant deletion semantics;
- legal/contractual retention overrides where applicable.

Backups SHALL be tested through restoration, not merely creation.

## 7.11 Administrative impersonation

If administrators can impersonate users:

- require privileged authorization;
- clearly indicate impersonation state;
- audit start/stop;
- prevent privilege laundering;
- preserve original administrator identity in audit events;
- constrain especially sensitive operations where appropriate.

---

# 8. Experience-quality contract

Every material interface SHALL be evaluated against the following canonical dimensions.

| Dimension | Required property |
|---|---|
| **Utility** | Every prominent element supports a real user goal, decision, state, or necessary context |
| **Effectiveness** | Intended tasks can be completed correctly and completely with clear outcome feedback |
| **Efficiency** | Common workflows avoid unnecessary repetition, decisions, navigation, scanning, and waiting |
| **Learnability** | Controls, terminology, placement, and interaction patterns are predictable and understandable |
| **Agency** | Consequential actions preserve meaningful control and disclose consequences |
| **Trustworthiness** | System state, uncertainty, success, failure, freshness, and limitations are represented truthfully |
| **Information Quality** | Information is accurate, relevant, sufficiently complete, current enough, and appropriately prioritized |
| **Accessibility** | Interfaces remain perceivable, operable, understandable, and robust |
| **Adaptability** | Interfaces tolerate legitimate variation in content, viewport, roles, themes, localization, and data volume |
| **Resilience** | Recoverable failures preserve work and provide coherent recovery |
| **Craftsmanship** | Implementation and interaction details are deliberate, consistent, precise, and maintainable |
| **Aesthetic Quality** | Typography, spacing, contrast, density, rhythm, hierarchy, and surfaces form a coherent whole |
| **Experiential Appropriateness** | Interaction weight and information density fit task frequency, risk, expertise, urgency, and context |

## 8.1 Conflict resolution

When these qualities materially conflict, resolve them in this order:

```text
1. user safety
2. security and privacy
3. factual / transactional correctness
4. accessibility
5. task effectiveness
6. agency and trustworthiness
7. information quality
8. resilience
9. efficiency and learnability
10. adaptability
11. craftsmanship
12. aesthetic refinement
```

A lower-order preference SHALL NOT weaken a higher-order requirement.

## 8.2 Destructive actions

High-consequence or irreversible actions SHALL communicate their consequences.

Where the domain permits it, reversibility SHOULD be preferred over confirmation ceremony.

Low-risk, easily reversible actions SHOULD NOT receive unnecessary confirmation friction.

---

# 9. Production and security envelope

## 9.1 Transport and endpoint

Production SHALL use HTTPS.

WebSocket origin validation SHALL remain appropriately configured.

Trusted proxy headers SHALL be accepted only from known infrastructure.

Production host configuration SHALL be explicit.

## 9.2 CSRF

Browser session routes and forms SHALL preserve Phoenix CSRF protections.

Machine-facing APIs or webhooks requiring different trust models SHOULD use separate pipelines rather than weakening browser security.

## 9.3 Sessions

Production session cookies SHALL use appropriate:

- secure transport;
- `Secure`;
- `HttpOnly` where applicable;
- SameSite policy;
- signing/encryption;
- lifetime;
- scope.

Secrets and signing material SHALL come from runtime secret management.

## 9.4 Security headers

Production SHALL preserve Phoenix secure browser headers and SHOULD deploy a reviewed CSP.

CSP SHOULD constrain:

```text
default sources
scripts
connections
frames
objects
images
fonts
styles
base URI
```

Third-party browser dependencies SHALL be treated as trust-boundary expansions.

Avoid `unsafe-eval`.

Minimize `unsafe-inline`.

## 9.5 Resource controls

Bound all attacker-influenceable expensive resources.

Applicable controls include:

- HTTP body size;
- upload size/count;
- pagination size;
- query complexity;
- websocket/channel usage;
- external HTTP timeouts;
- response-size limits;
- background-job concurrency;
- export size;
- database timeouts;
- LiveView collection size.

## 9.6 Rate limits

Abuse-sensitive actions SHOULD receive explicit rate limits.

High-priority examples:

- authentication;
- password recovery;
- OTP generation/verification;
- registration;
- invitations;
- email verification;
- public forms;
- uploads;
- expensive search;
- exports;
- external integrations;
- billing actions;
- privileged mutations.

Rate limiting supplements but never replaces authorization.

## 9.7 Secrets

Production secrets SHALL NOT be committed.

Mandatory production secrets SHOULD cause startup failure when missing rather than silently using development defaults.

## 9.8 Logging

Logs SHALL redact sensitive values including:

- passwords;
- OTPs;
- tokens;
- API keys;
- session credentials;
- authorization headers;
- recovery credentials;
- provider secrets;
- sensitive domain fields as required.

Whole event payloads SHOULD NOT be logged indiscriminately.

## 9.9 Audit events

Security-sensitive operations SHOULD create structured audit events where product risk warrants them.

Potential events include:

- authentication/security changes;
- role changes;
- tenant ownership changes;
- billing changes;
- API-key lifecycle;
- exports;
- administrative actions;
- impersonation;
- destructive operations.

Audit records SHOULD capture actor, tenant, action, target, time, result, and correlation data without storing secrets.

## 9.10 Supply chain

CI SHALL audit locked dependencies.

At minimum:

```bash
mix hex.audit
```

Known vulnerabilities SHALL not be silently ignored.

Git dependencies, if necessary, SHALL use reviewed immutable revisions.

Frontend dependencies SHALL be subject to equivalent review.

## 9.11 Static security analysis

A Phoenix-aware static analysis tool such as Sobelow SHOULD be used for production SaaS projects.

Findings SHALL be reviewed, not globally suppressed to obtain a passing build.

Secret scanning SHOULD be enabled for source history and CI.

## 9.12 Deployment

Production SHOULD use an immutable release artifact.

The artifact SHOULD identify:

- source revision;
- `mix.lock`;
- Elixir version;
- OTP version;
- Phoenix version;
- LiveView version;
- Petal version;
- asset revision.

Database migrations SHALL be explicit release operations.

Rolling deployments requiring zero downtime SHOULD follow expand/contract schema evolution.

## 9.13 Observability

Production observability SHOULD cover:

- HTTP latency/errors;
- LiveView mount/event failures;
- database latency/pool saturation;
- external-service latency/errors;
- job failures;
- authentication failures;
- authorization failures;
- rate limits;
- memory;
- scheduler pressure;
- mailbox growth where relevant;
- deployment identity.

Metric labels SHALL use bounded cardinality.

## 9.14 Health and resilience

Separate:

```text
liveness
readiness
dependency health
```

Temporary third-party failure SHOULD NOT cause destructive restart loops.

Every external request SHALL have a timeout.

Retries SHALL be bounded and consistent with idempotency guarantees.

---

# 10. Assurance matrix

Every normative requirement SHALL be supported by objective evidence.

| Requirement domain | Assurance evidence |
|---|---|
| Runtime/version contract | Runtime version output + lockfile + CI environment |
| Petal compatibility | Successful dependency resolution + compile + representative component tests |
| Petal API correctness | Installed-version schema/source verification + compile |
| Asset integration | Production asset build + browser smoke test |
| Authentication | Controller/LiveView tests for unauthenticated and authenticated cases |
| Authorization | Positive and negative operation tests |
| Tenancy | Cross-tenant negative tests |
| Entitlements | Server-side entitlement tests including forged client payloads |
| Input validation | Changeset/domain tests + hostile-input cases |
| XSS/output safety | Rendering tests + targeted security tests |
| CSRF | Integration tests where custom browser endpoints exist |
| Session policy | Production configuration inspection |
| CSP/headers | Deployment/header inspection |
| Rate limiting | Automated abuse-boundary tests where practical |
| Database integrity | Constraint/transaction tests |
| External integrations | Adapter tests, timeout/error/idempotency tests |
| Background work | Retry/idempotency tests |
| Uploads | Size/type/authentication tests when enabled |
| SSRF | Destination/protocol/redirect tests when outbound URL capability exists |
| Webhooks | Signature + replay/idempotency tests when enabled |
| Billing | Provider-state and entitlement tests when enabled |
| Accessibility | Automated tests + keyboard testing + manual semantic review |
| Responsive behavior | Browser tests at representative widths |
| Light/dark themes | Browser or visual verification |
| Experience quality | Task/state review against Section 8 |
| Logging/privacy | Redaction tests/configuration review |
| Dependency security | `mix hex.audit` and applicable frontend audit |
| Static security | Sobelow or equivalent review |
| Deployment reproducibility | Immutable artifact metadata |
| Recovery/resilience | Error-path and retry tests |
| Data lifecycle | Backup/restore/deletion tests where applicable |
| Admin impersonation | Authorization + audit tests where enabled |

## 10.1 Required build evidence

The project SHALL execute the equivalent of:

```bash
mix deps.get
mix hex.audit
mix format --check-formatted
mix compile --warnings-as-errors
mix test
```

Production asset compilation SHALL also pass using the project's defined build command or alias.

If the project defines:

- Sobelow;
- Credo;
- Dialyzer;
- browser tests;
- accessibility checks;
- frontend audits;

those configured release gates SHALL pass according to project policy.

The architecture SHALL require the capability, not a fictitious command that the repository does not expose.

## 10.2 Browser assurance

Critical workflows SHALL be exercised in a real browser where browser testing infrastructure is available.

At minimum verify applicable:

- mobile/narrow layout;
- desktop layout;
- light mode;
- dark mode;
- keyboard operation;
- focus behavior;
- forms and validation;
- loading state;
- empty state;
- error state;
- consequential-action flow;
- Petal overlays;
- menus/popovers/comboboxes;
- navigation shell;
- data tables;
- date controls;
- application hooks.

Browser-console errors on critical flows SHALL be investigated before release.

## 10.3 Accessibility assurance

Accessibility assurance SHALL combine:

```text
automated checks
+
keyboard testing
+
manual semantic inspection
+
screen-reader checks for critical flows where practical
```

Passing an automated scanner alone SHALL NOT establish accessibility conformance.

---

# 11. Release acceptance condition

A release conforms to this architecture only when all applicable normative requirements have evidence in the assurance matrix.

At minimum:

1. approved Elixir and OTP versions are used;
2. Phoenix and LiveView are on patched compatible releases;
3. Petal resolves within the approved 4.16.x line;
4. `mix.lock` is committed and matches the tested release;
5. dependency auditing passes or documented exceptions are explicitly approved;
6. formatting passes;
7. compilation passes without newly introduced warnings;
8. relevant automated tests pass;
9. production assets build;
10. Petal styles and required hooks load correctly;
11. Petal component APIs match the installed version;
12. no unnecessary competing generic design system has been introduced;
13. authentication works across the required HTTP/LiveView lifecycle;
14. consequential operations enforce server-side authorization;
15. cross-tenant access is negatively tested where tenancy exists;
16. client-visible entitlements cannot bypass server authorization;
17. untrusted rendered content has a defined escaping/sanitization path;
18. CSRF/session/origin protections remain appropriate;
19. security-sensitive resources are bounded;
20. abuse-sensitive workflows are rate-limited where appropriate;
21. secrets are runtime-managed;
22. sensitive log data is redacted;
23. external integrations have explicit timeout/error behavior;
24. retryable actions are idempotent where required;
25. critical persistence invariants are backed by database constraints where appropriate;
26. required conditional capability contracts are activated and tested;
27. critical interfaces meet accessibility requirements;
28. critical interfaces function at required viewport sizes;
29. light/dark behavior is coherent where supported;
30. recoverable failures provide coherent recovery;
31. system state is represented truthfully;
32. the primary user workflows satisfy the experience-quality contract;
33. the release artifact is identifiable and reproducible;
34. no known placeholder behavior is represented as complete;
35. no presentation-layer behavior is relied upon as a security boundary.

## Final invariant

The architecture is conformant when:

```text
Petal defines reusable presentation primitives.

The application design system defines product language.

LiveView owns interactive presentation state.

Phoenix owns web infrastructure.

Application contexts own business operations.

Authorization owns permission decisions.

Tenancy owns resource boundaries.

Ecto and PostgreSQL own persistence integrity.

OTP owns process supervision and failure containment.

Infrastructure owns secure execution and secret delivery.

The browser owns no authority.
```

No lower layer may silently assume responsibility belonging to another layer.

No requirement is satisfied merely because the UI makes an invalid operation difficult to discover.

Every material invariant must be both operationally implementable and objectively verifiable.
