<!--
ARCH-002: reference architecture (structure) for the target Findependence application.
Source: provided by ACT-001 in session, 2026-09-29, with "Use this as reference architecture for target".
Recorded by ACT-002 (REV-081, CHG-079). ARCH-001 remains the normative text (its SHALLs); ARCH-002 is the
structure that text is applied to. Its implications (the trust model it assumes, the local-first interface,
the new external parties it names) are listed as open questions in REV-081, not decided here.
The diagram below is ACT-001's, unedited.
-->

# Target structure (ARCH-002)

```
                         EXTERNAL CLIENTS
             ┌──────────────┬───────────────┐
             │              │               │
         iOS / Siri      Android          Alexa
             │              │               │
             └──── HTTPS ───┤        verified HTTPS
                            │               │
                            ▼               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    ELIXIR / PHOENIX APPLICATION                 │
│                                                                 │
│  MyAppWeb                                                       │
│                                                                 │
│   LiveView + Petal ────────────────┐                            │
│          │                          │                            │
│          │ direct function calls   │                            │
│          │                          │                            │
│   JSON API controllers ────────────┤                            │
│   Alexa adapter ───────────────────┤                            │
│   Provider webhook adapters ───────┤                            │
│                                    ▼                            │
│                    PUBLIC CONTEXT BOUNDARIES                    │
│                                                                 │
│      Identity · Households · Ledger · Budgets · Institutions   │
│                                                                 │
│                scope · authorization · operations               │
│                              │                                  │
│                              ▼                                  │
│                DOMAIN / PERSISTENCE LOGIC                       │
│           plain functions · schemas · changesets · queries     │
│                              │                                  │
│                              ▼                                  │
│                         Ecto Repo                               │
│                              │                                  │
│                       Repo.transact                             │
│                              │                                  │
│                ┌─────────────┴────────────┐                     │
│                ▼                          ▼                     │
│          PostgreSQL                  Oban jobs                  │
│       canonical truth            durable consequences          │
│                │                          │                     │
│                │                          ▼                     │
│                │                 Provider adapters             │
│                │                          │                     │
│                │                         Req                    │
│                │                                                │
│                └── after commit ──► PubSub                     │
│                                      │                          │
│                                      ▼                          │
│                                 LiveView refresh                │
└─────────────────────────────────────────────────────────────────┘
```
