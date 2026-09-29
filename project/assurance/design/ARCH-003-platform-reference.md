<!--
ARCH-003: domain-neutral platform reference architecture; the final target reference architecture.
Source: provided by ACT-001 in session, 2026-09-29, with "this is final reference architecture target.
propose updates to head in this direction." Recorded by ACT-002 (REV-082, CHG-080).
How the project moves toward it, and how it relates to ARCH-001 and ARCH-002, is proposed in CP-020.
Findependence-specific meaning enters through a domain profile (section 37), proposed in CP-020 as DP-001.
The text below is ACT-001's, unedited.
-->

# Normalized Domain-Neutral Platform Reference Architecture

## 0. Status and purpose

This document defines the canonical platform architecture for a secure, privacy-conscious, multi-tenant SaaS product implemented primarily with Elixir and Phoenix and exposed through web, mobile, assistant, and external-integration surfaces.

This specification is **domain-neutral**.

It defines:

- execution boundaries;
- responsibility ownership;
- trust boundaries;
- persistence responsibilities;
- asynchronous work;
- realtime signaling;
- client integration;
- security and privacy contracts;
- operational contracts;
- assurance requirements.

It SHALL NOT define product-specific domain concepts.

A concrete product SHALL specialize this architecture through a separate **domain profile**.

---

# 1. Architectural quality requirements

The architecture SHALL be:

### Normalized

Every material concept has one canonical definition and one canonical responsibility.

### Irreducible

No architectural concept or mechanism exists without a material responsibility that requires it.

### Materially complete

Every responsibility required for the declared platform scope is represented.

### Internally coherent

No two components claim contradictory ownership of authority, state, behavior, or lifecycle.

### Operationally realizable

Every architectural requirement can be implemented using the selected technology platform.

### Assurable

Every material requirement can be demonstrated through objective evidence.

These criteria apply to both the architecture itself and any domain architecture derived from it.

---

# 2. Canonical platform topology

```text
                         REMOTE CLIENTS
                iOS · Android · Assistants
                            │
                      HTTPS / protocol
                            │
                            ▼
┌──────────────────────────────────────────────────────────────┐
│                 ELIXIR / PHOENIX APPLICATION                │
│                                                              │
│  PRESENTATION / TRANSPORT                                    │
│                                                              │
│  LiveView + Web Components ─────────┐                        │
│  JSON/HTTP API ─────────────────────┤                        │
│  Assistant adapters ────────────────┤                        │
│  Webhook adapters ──────────────────┤                        │
│                                    ▼                        │
│                        PUBLIC CONTEXT API                    │
│                                                              │
│                Platform + Domain Contexts                    │
│                                    │                        │
│                                    ▼                        │
│                           DOMAIN RULES                       │
│                                                              │
│        invariants · policies · transitions · calculations   │
│                                    │                        │
│                                    ▼                        │
│                           PERSISTENCE                        │
│                                                              │
│               Ecto · Queries · Repo · Transactions          │
│                                    │                        │
│                 ┌──────────────────┼─────────────────┐       │
│                 ▼                  ▼                 ▼       │
│            PostgreSQL            Oban              PubSub    │
│          canonical state     durable work     realtime signal│
│                                    │                        │
│                                    ▼                        │
│                       EXTERNAL ADAPTERS                      │
│                         Req / SDKs                           │
└──────────────────────────────────────────────────────────────┘
```

The diagram represents **logical responsibility and dependency direction**.

It does not require every box to become a separate process, package, service, directory, or abstraction layer.

---

# 3. Canonical dependency direction

The logical dependency direction SHALL be:

```text
Presentation / Transport
          ↓
Public Context API
          ↓
Domain Rules
          ↓
Persistence
          ↓
Durable Infrastructure
```

Supporting infrastructure MAY be invoked where required.

Infrastructure SHALL NOT define higher-level product semantics merely because it implements them.

---

# 4. Canonical application boundary

The **public context API** is the canonical application boundary.

Equivalent product capabilities SHALL converge on the same public application operation regardless of transport.

```text
LiveView ─────────────────┐
HTTP API ─────────────────┤
Mobile ───────────────────┤
Assistant adapter ────────┤
Webhook/integration ──────┤
Administrative surface ───┤
                         ▼
               Public Context Operation
```

The network API is NOT the application boundary.

It is one transport adapter into the application boundary.

---

# 5. One-operation invariant

Every materially equivalent product operation SHALL have one canonical semantic implementation.

For example:

```elixir
DomainContext.perform_operation(scope, attributes)
```

The architecture SHALL NOT create independent implementations such as:

```text
perform_operation_from_liveview
perform_operation_from_mobile
perform_operation_from_assistant
perform_operation_from_admin
```

when those operations represent the same product behavior.

Transport-specific parsing, verification, serialization, presentation, and error translation MAY differ.

Product semantics SHALL not.

---

# 6. LiveView architecture

LiveView executes inside the Phoenix application.

It SHALL call public context operations directly in-process.

```text
Browser
   ↓
LiveView
   ↓
Public Context Operation
```

It SHALL NOT call the application's external HTTP API merely to obtain transport symmetry.

LiveView MAY own presentation concerns such as:

```text
modal state
selected tabs
temporary form state
pagination presentation
loading state
UI-specific validation feedback
```

LiveView SHALL NOT exclusively own product capabilities, domain invariants, authorization rules, or durable state transitions.

If an operation is a genuine product capability, a non-LiveView adapter SHALL be capable of reaching the same canonical application operation.

---

# 7. Remote transport architecture

Remote clients SHALL enter through transport adapters.

```text
Remote Client
      ↓
HTTP / protocol
      ↓
Transport Adapter
      ↓
trusted scope construction
      ↓
Public Context Operation
```

A transport adapter owns transport concerns such as:

```text
request decoding
protocol validation
transport authentication
request-origin verification
serialization
HTTP status mapping
response encoding
```

It SHALL NOT become an alternate domain layer.

---

# 8. Public context architecture

Contexts SHALL organize coherent product or platform capabilities.

They SHALL NOT be created mechanically:

```text
one context per table
one context per web page
one context per controller
one context per transport
```

A public context operation represents an application capability.

Contexts MAY coordinate:

```text
authorization
domain rules
persistence
external adapters
durable jobs
```

as necessary to perform that capability.

Internal implementation detail SHALL remain private unless another context genuinely requires a stable collaboration boundary.

---

# 9. Platform contexts versus domain contexts

The application MAY contain two categories of contexts.

## Platform contexts

These represent domain-independent SaaS capabilities, for example:

```text
Identity
Tenancy
Entitlements
Subscriptions
Notifications
Administration
```

Only contexts actually required by the product SHALL exist.

## Domain contexts

These are supplied by the product's domain profile.

The platform architecture SHALL NOT prescribe their names or semantics.

For example:

```text
Platform Reference Architecture
             │
             ▼
       Domain Profile
             │
             ▼
     Product-Specific Contexts
```

This keeps the platform reusable without weakening the domain model.

---

# 10. Domain rules

Domain rules define product meaning.

They MAY include:

```text
invariants
state transitions
policies
calculations
cross-entity rules
domain validation
idempotency semantics
```

Domain logic SHOULD ordinarily use plain Elixir modules and functions.

A domain concept SHALL NOT become a GenServer merely for organizational purposes.

Processes SHALL be introduced when runtime properties require them, such as:

```text
concurrency
independent lifecycle
failure containment
long-lived mutable runtime state
supervision
```

The architecture distinguishes responsibility without requiring ceremonial abstraction.

---

# 11. Domain versus persistence

Domain meaning and persistence representation are distinct responsibilities.

An Ecto schema MAY also be a useful domain data structure where the fit is natural.

It SHALL NOT be assumed that:

```text
database schema
=
complete domain model
```

Likewise:

```text
changeset
=
entire domain-validation model
```

is not an architectural invariant.

Simple validation may naturally belong in changesets.

Cross-resource or operation-level invariants MAY belong in domain/application functions coordinating several persistence operations.

The architecture SHALL introduce additional domain representations only when they materially improve correctness, clarity, reuse, or assurance.

---

# 12. Persistence architecture

Persistence SHALL provide durable state and transactional integrity.

The default persistence stack is:

```text
Ecto
  ↓
Repo
  ↓
PostgreSQL
```

PostgreSQL is the canonical authority for durable server-owned state.

Ecto owns application interaction with that state through:

```text
schemas
changesets
queries
constraints
transactions
```

A cache, process, PubSub message, client representation, background job, or external provider record SHALL NOT silently become a competing source of canonical state.

---

# 13. Transaction boundaries

Use the simplest mechanism capable of enforcing the required invariant.

Conceptually:

```text
single persistence operation
        → ordinary Repo operation

multi-step atomic operation
        → Repo transaction

composable/dynamic atomic workflow
        → Ecto.Multi where advantageous

concurrent durable invariant
        → database constraint / locking /
          appropriate transaction semantics
```

The architecture SHALL NOT require `Ecto.Multi` for every operation.

The architecture SHALL NOT use an OTP process as a substitute for durable database concurrency guarantees.

---

# 14. Multi-tenancy

Where the product is multi-tenant, tenancy is a canonical resource boundary.

A trusted server-side scope SHALL identify the applicable actor and tenant.

```text
authenticated identity
        ↓
trusted scope
        ↓
context operation
        ↓
tenant-scoped resource access
```

Tenant identity supplied directly by an untrusted client SHALL NOT itself establish authority.

Where appropriate, persistence constraints SHOULD reinforce tenant integrity so that invalid cross-tenant relationships cannot be created merely because application code contains a defect.

Application authorization and database integrity are complementary controls.

---

# 15. Authority model

The application SHALL have one logical authority model.

A consequential decision SHOULD derive from the applicable combination of:

```text
actor
tenant
operation
resource
resource state
entitlement
policy
```

Authentication establishes identity.

Tenancy establishes resource scope.

Entitlements establish available capability.

Authorization determines whether the operation is permitted.

These concerns SHALL remain semantically distinct while contributing to one decision path.

Client-visible state SHALL NOT constitute authority.

Therefore:

```text
hidden control        ≠ authorization
disabled control      ≠ authorization
client role field     ≠ authorization
client tenant ID      ≠ authorization
missing navigation    ≠ authorization
assistant intent      ≠ authorization
```

---

# 16. Identity and session contract

Identity establishes trustworthy actors for the authority model.

```text
credential
    ↓
authentication
    ↓
session/token
    ↓
trusted actor
    ↓
scope
    ↓
authorization
```

The system SHALL explicitly define:

```text
authentication
session creation
session rotation
expiration
revocation
credential changes
account recovery
privileged identity
device/session management where applicable
```

Local device authentication MAY protect access to a client application.

It SHALL NOT substitute for server-side authorization.

---

# 17. Durable asynchronous work

Oban SHALL be the default mechanism for server-side work that must survive application-process or node failure.

Appropriate examples include:

```text
external synchronization
notification delivery
exports
email
scheduled work
external callbacks
long-running enrichment
```

Where a canonical state transition and required asynchronous consequence must not diverge, both SHOULD be durably established within the same database transaction when practical.

```text
transaction
   │
   ├── state mutation
   └── durable Oban job
```

A generic message broker, event store, outbox, workflow engine, or event-bus abstraction SHALL NOT be introduced unless a concrete requirement justifies it.

---

# 18. External side effects

Remote side effects SHOULD generally execute outside the transaction that establishes canonical state.

Avoid:

```text
BEGIN

change canonical state
call external service
wait for network
perform unrelated external action

COMMIT
```

Prefer:

```text
database transaction
       │
       ├── canonical mutation
       └── durable consequence
                 │
              COMMIT
                 │
                 ▼
            background work
                 │
                 ▼
          external adapter
```

Every consequential external mutation SHALL define appropriate:

```text
timeout
retry policy
idempotency
backoff
failure classification
```

Retry semantics SHALL reflect the external operation's actual safety properties.

---

# 19. Realtime signaling

Phoenix PubSub SHALL provide transient realtime distribution.

Typical flow:

```text
canonical state changes
        ↓
successful commit
        ↓
PubSub notification
        ↓
interested connected processes refresh
```

PubSub SHALL NOT constitute:

```text
canonical state
durable work
guaranteed delivery
audit history
event storage
```

A missed PubSub message SHALL NOT compromise durable correctness.

---

# 20. Events

A domain event is a semantic statement that something occurred.

The existence of domain-event vocabulary SHALL NOT automatically require:

```text
event sourcing
event store
event broker
event bus
projection engine
```

Events MAY initially exist only as useful domain/application semantics.

Durable event infrastructure SHALL be introduced only when required by concrete needs such as:

```text
independent durable consumers
external event distribution
event replay
temporal reconstruction
event sourcing
```

This preserves architectural irreducibility.

---

# 21. Derived state and projections

A projection is any representation derived from canonical state.

It MAY be implemented as:

```text
ordinary query
database aggregate
materialized view
cache
specialized read model
```

The architecture SHALL NOT require a dedicated projection subsystem without a concrete requirement.

Every material derived representation SHALL have identifiable canonical inputs.

Derived state SHALL NOT silently become competing canonical state.

---

# 22. External integrations

Every external system SHALL be isolated behind an adapter appropriate to its protocol.

Outbound:

```text
Context / Domain Operation
          ↓
Integration Boundary
          ↓
Provider Adapter
          ↓
Req / SDK
          ↓
External System
```

Inbound:

```text
External System
       ↓
Transport verification
       ↓
Provider normalization
       ↓
Public Context Operation
       ↓
Canonical state
```

Provider-specific data SHALL be normalized before becoming domain state when its external representation does not itself constitute the application's canonical model.

---

# 23. Mobile architecture

Native mobile clients SHALL remain remote clients of the authoritative application.

They MAY maintain a local source of truth for device rendering.

This creates two intentionally different scopes:

```text
SYSTEM-WIDE AUTHORITY
server canonical state
        ↓ synchronization
DEVICE-LOCAL SOURCE OF TRUTH
local cache/repository
        ↓
mobile UI
```

Device-local rendering authority SHALL NOT imply system-wide domain authority.

---

# 24. Offline operation model

Offline data SHALL be classified explicitly.

It is one of:

```text
cached authoritative state
pending user intent
genuinely device-local state
```

Offline mutations SHOULD normally be represented as pending operations:

```text
user operation
      ↓
pending local intent
      ↓
connectivity restored
      ↓
remote adapter
      ↓
canonical context operation
      ↓
accepted / rejected / conflicted
      ↓
local synchronization
```

Optimistic presentation MAY occur.

It SHALL remain distinguishable from authoritative acceptance when that distinction is material.

---

# 25. Siri / Apple system integration

Where Siri integration is required:

```text
Siri / Apple system
        ↓
App Intent
        ↓
iOS application adapter
        ↓
authenticated remote operation
        ↓
Phoenix transport adapter
        ↓
Public Context Operation
```

App Intent definitions SHALL remain iOS integration concerns.

They SHALL NOT create a parallel product domain.

---

# 26. Alexa integration

Where Alexa integration is required:

```text
Alexa service
      ↓
HTTPS request
      ↓
Alexa request verification
      ↓
account/identity resolution
      ↓
Phoenix adapter
      ↓
Public Context Operation
```

Alexa protocol semantics SHALL terminate at the adapter boundary.

Request authenticity and replay protections required by the Alexa transport SHALL be established before treating the request as a trusted application input.

Assistant convenience SHALL NOT bypass normal application authority.

---

# 27. Web presentation and design system

The web implementation SHALL use:

```text
Phoenix
   ↓
LiveView
   ↓
application-owned design system
   ↓
Petal Components
```

Petal is a presentation implementation dependency.

It SHALL NOT define the product domain, authority model, application boundary, or persistence model.

The application design system SHALL sit conceptually above any particular component library.

---

# 28. Cross-platform design contract

The product SHALL maintain one semantic design language across platforms while permitting platform-appropriate rendering.

```text
               Semantic Design System
                        │
          ┌─────────────┼─────────────┐
          ▼             ▼             ▼
         Web           iOS         Android
       Petal/UI      SwiftUI       Compose
```

Assistant surfaces MAY implement the same semantic concepts conversationally.

Shared semantics SHOULD include, where applicable:

```text
information hierarchy
terminology
interaction states
risk states
privacy states
confirmation semantics
error semantics
accessibility requirements
```

Code reuse SHALL NOT take precedence over security, correctness, accessibility, or platform appropriateness.

---

# 29. Cryptography and secrets

The platform SHALL explicitly govern:

```text
secret generation
storage
runtime delivery
access
rotation
revocation
retirement
```

Secrets SHALL NOT be committed to source or exposed through client-visible configuration.

Cryptographic mechanisms SHALL use established implementations rather than product-specific cryptographic invention.

Storage and transport protection SHALL follow the product threat model.

---

# 30. Privacy and data lifecycle

Every retained data class SHALL define:

```text
purpose
authority
allowed access
retention
export behavior
deletion behavior
backup behavior
logging/telemetry policy
```

The architecture SHALL minimize unnecessary:

```text
collection
storage
duplication
transmission
disclosure
retention
```

Telemetry SHALL remain logically distinct from canonical product state.

Caches, derived representations, exports, and backups SHALL have defined lifecycle relationships with their canonical inputs.

---

# 31. Resource and abuse governance

Authorization answers:

```text
May this actor perform this operation?
```

Resource governance answers:

```text
How much permitted activity may safely occur?
```

The platform SHALL bound attacker- or user-influenceable resources where material.

Examples MAY include:

```text
authentication attempts
request body size
uploads
pagination
search complexity
exports
concurrent jobs
external requests
timeouts
response sizes
connection usage
```

An authorized actor SHALL NOT implicitly receive unlimited resource consumption.

---

# 32. Operations and recovery

Production architecture SHALL define:

```text
release identity
dependency locking
runtime configuration
migration strategy
rollback strategy
backup
restore
recovery objectives
dependency failure behavior
health signaling
```

A backup SHALL NOT be considered proven recovery until restoration has been exercised.

Database migration strategy SHALL account for deployed application compatibility.

External dependency failure SHALL be bounded and SHALL not create uncontrolled retry or resource amplification.

---

# 33. Observability and audit

Operational observability and security audit are distinct.

## Observability

Observability SHOULD expose sufficient information to understand:

```text
request health
runtime health
database health
job health
integration health
authorization failures
resource exhaustion
deployment identity
```

Sensitive domain payloads SHALL NOT become ordinary telemetry by default.

## Audit

Where auditability is required, audit records SHOULD identify applicable:

```text
actor
tenant
operation
resource
time
channel
outcome
```

Audit records SHALL NOT contain secrets.

General logs SHALL NOT substitute for a deliberate audit model.

---

# 34. Failure model

Failures SHOULD be classified into stable application-level categories where useful.

Examples:

```text
validation failure
unauthenticated
unauthorized
not found
conflict
rate limited
external dependency unavailable
temporary infrastructure failure
permanent domain rejection
```

Transport adapters translate these outcomes into their protocol-specific representation.

Domain/application code SHALL NOT need to return LiveView-, JSON-, Siri-, or Alexa-specific error models.

---

# 35. Assurance model

Every material architectural requirement SHALL map to objective evidence.

Representative mappings include:

| Requirement | Evidence |
|---|---|
| Canonical application boundary | architectural/dependency tests and code review |
| Equivalent operations converge | adapter-to-context integration tests |
| Authorization | positive and negative authorization tests |
| Tenant isolation | cross-tenant negative tests |
| Domain invariants | unit/property/integration tests |
| Persistence integrity | constraints and transactional tests |
| Durable work | failure/retry/idempotency tests |
| External integrations | timeout/retry/malformed-response tests |
| Mobile synchronization | offline/reconnect/conflict tests |
| Secret protection | source/build/artifact scanning |
| Session revocation | integration tests |
| Data lifecycle | retention/export/deletion tests |
| Recovery | actual restore exercise |
| Resource limits | boundary/abuse/load tests |
| Log privacy | redaction inspection/tests |
| Accessibility | automated and manual interaction tests |
| Deployment integrity | release metadata and migration verification |

A requirement without a practical verification mechanism is incomplete unless explicitly accepted as non-assurable.

---

# 36. Architectural prohibitions

The following violate this reference architecture:

```text
LiveView-only product operations

mobile-only duplicate domain rules

assistant-specific duplicate domain rules

controllers containing canonical business logic

HTTP used internally solely to reach code in the same application

one authorization implementation per transport

client-provided authority trusted without server validation

cache treated as canonical durable state

PubSub treated as durable delivery

Oban job treated as canonical product state

GenServer introduced solely as a service-layer abstraction

database model automatically assumed to be the entire domain model

external provider schema automatically treated as canonical domain schema

network side effects unnecessarily performed inside long database transactions

generic event infrastructure introduced without a requirement

generic repository/service/command-bus layers introduced only for architectural symmetry
```

---

# 37. Domain-profile contract

A concrete product derives from this reference architecture by supplying a **domain profile**.

The domain profile SHALL define:

```text
domain vocabulary
domain contexts
canonical domain state
domain invariants
state transitions
calculations
domain-specific authorization
domain-specific audit requirements
domain-specific privacy requirements
domain-specific assurance evidence
```

The domain profile SHALL NOT redefine the platform's transport, trust, persistence, or execution semantics without an explicit architectural exception.

Conceptually:

```text
REFERENCE PLATFORM
        │
        ├── Identity
        ├── Tenancy
        ├── Application Boundary
        ├── Persistence
        ├── Async / Realtime
        ├── Security / Privacy
        └── Operations / Assurance
        │
        ▼
DOMAIN PROFILE
        │
        ├── product-specific contexts
        ├── product-specific rules
        ├── product-specific state
        └── product-specific semantics
        │
        ▼
PRODUCT
```

A personal-finance system, accounting system, commerce system, healthcare application, project-management system, or other SaaS product can therefore specialize the same platform architecture without contaminating the platform definition with its domain vocabulary.

---

# 38. Technology mapping

The current implementation mapping is:

```text
Web framework             → Phoenix
Server-rendered UI         → Phoenix LiveView
Web component layer        → Petal Components
Application boundary       → Phoenix/Elixir contexts
Domain implementation      → Elixir modules/functions
Persistence mapping        → Ecto
Durable database           → PostgreSQL
Durable asynchronous work  → Oban
Transient realtime         → Phoenix PubSub
Outbound HTTP              → Req / justified provider SDK
iOS presentation           → SwiftUI
Android presentation       → Jetpack Compose
Apple assistant integration→ App Intents
Alexa integration          → verified Phoenix HTTPS adapter
```

These are implementation choices beneath the architectural contracts.

Replacing an implementation SHOULD NOT require redefining product semantics unless the replacement materially changes a declared capability or constraint.

---

# 39. Canonical responsibility map

| Responsibility | Canonical home |
|---|---|
| Web presentation | LiveView + application design system |
| Web UI primitives | Petal Components |
| Remote HTTP transport | Phoenix web layer |
| Siri/system transport | iOS App Intents |
| Alexa transport | Alexa/Phoenix adapter |
| Product operation | Public context function |
| Domain meaning | Domain rules |
| Trusted identity | Identity/session boundary |
| Tenant scope | Trusted application scope |
| Authorization | Application/domain operation |
| Durable canonical state | PostgreSQL |
| Persistence interaction | Ecto/Repo |
| Atomic durable consistency | PostgreSQL transaction through Ecto |
| Durable asynchronous work | Oban |
| Realtime notification | PubSub |
| External translation | Provider/integration adapter |
| Device rendering state | Client-local repository/state |
| Offline uncommitted mutation | Pending client operation |
| Product visual semantics | Application design system |
| Runtime secrets | Approved secret-management boundary |
| Operational telemetry | Observability infrastructure |
| Security-sensitive history | Audit model |

---

# 40. Final normalized execution model

```text
                  HUMAN / EXTERNAL SYSTEM
                           │
                           ▼
                PRESENTATION / TRANSPORT
                           │
                           ▼
                  PUBLIC CONTEXT API
                           │
                           ▼
                       AUTHORITY
                           │
                           ▼
                     DOMAIN RULES
                           │
                           ▼
                      PERSISTENCE
                           │
                           ▼
                   CANONICAL STATE
                           │
             ┌─────────────┴─────────────┐
             ▼                           ▼
       DURABLE CONSEQUENCE        REALTIME SIGNAL
            Oban                      PubSub
             │
             ▼
      External Adapter
```

For LiveView:

```text
Browser
   ↓
LiveView
   ↓
Public Context API
```

For remote clients:

```text
Remote Client
     ↓
HTTP Adapter
     ↓
Public Context API
```

For inbound integrations:

```text
External System
      ↓
Verified Adapter
      ↓
Public Context API
```

All converge before canonical application semantics begin.

---

# 41. Final architectural invariants

The platform SHALL maintain:

```text
one canonical application boundary

one semantic implementation
per equivalent product capability

one authority model

one canonical durable-state authority

one domain definition
for each domain rule

one persistence responsibility

one durable asynchronous-work mechanism
unless requirements justify another

one realtime-signaling role

one trusted identity/session model

one tenancy model

one privacy/data-lifecycle model

one operations/recovery model

one semantic design language

one assurance model
```

Different clients MAY use different transports.

Different platforms MAY use different renderers.

Different integrations MAY use different protocols.

Different domains MAY define entirely different business concepts.

Those differences SHALL terminate at their appropriate boundary and SHALL NOT create competing definitions of canonical application behavior.

---

# 42. Reference-architecture acceptance condition

This reference architecture is conformant only if all of the following remain true:

**Normalized** — every material concept has one canonical home.

**Irreducible** — no component, abstraction, process, or infrastructure mechanism exists without a material responsibility.

**Materially complete** — application, trust, data, client, integration, security, privacy, operational, recovery, experience, and assurance responsibilities required by the declared platform scope are represented.

**Internally coherent** — no component requires contradictory ownership, authority, or state semantics.

**Operationally realizable** — every requirement maps to a concrete implementation mechanism.

**Assurable** — every material requirement has objective evidence or an explicitly documented assurance limitation.

The reference architecture SHALL remain domain-neutral.

Product-specific semantics SHALL enter through a derived domain profile rather than through modification of the platform's canonical responsibility model.
