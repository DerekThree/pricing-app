---
status: current
verified: 2026-08-29
tags:
  - reference
  - roadmap
---

# Current and planned system

The repository contains both implemented application code and future architecture. Keep those states explicit when designing a feature or explaining behavior.

| Capability | Current source | Planned or decided direction |
|---|---|---|
| Pricing Configuration | Implemented in the Spring Boot backend and PostgreSQL | Remains authoritative in the pricing backend |
| Dashboard | Implemented React Router SPA | Major dashboard convenience expansion is not the current architectural priority |
| Simulator | Implemented browser screen using backend date/options endpoints and synchronous `POST /batch` | Intended later to represent mocked upstream and downstream systems |
| Pricing Engine | `PrototypeRuleEngine` runs as a bean inside the backend | Separate Spring Boot worker processing persisted chunks |
| Configuration loading | Candidate Pricing Plans filtered by submitted Pricing Dates in PostgreSQL; remaining evaluation in Java | Evaluation boundary accepted by ADR 0004 |
| Pricing Batch storage | Not persisted by the current `/batch` path | Account Processor persists batches in PostgreSQL |
| Batch trigger | Full Pricing Batch is the synchronous HTTP request body | Generic HTTP work-available wake-up without `batchId` |
| Pricing Decisions | Returned in the synchronous HTTP response | Persisted recommendation data in PostgreSQL |
| Outbox and recovery | Not implemented | Transactional outbox, producer retry, and startup pending-work recovery |
| Transaction Processor | Not implemented | Mock external consumer of persisted recommendations |
| Rates | No current route, entity, migration, or dashboard screen | Mentioned in historical/planned material but not defined as a current domain capability |

## Accepted decisions versus implementation

[ADR 0004](../../../ADR/0004-choose-pricing-engine-evaluation-location.md) is both accepted and reflected in the current prototype: SQL filters candidate Pricing Plans, then Java owns exact resolution, validation, eligibility, calculation, and statuses.

[ADR 0005](../../../ADR/0005-Use-HTTP-for-batch-ready-notifications.md) is accepted architecture for later service boundaries. The current code has no batch-ready notification endpoint, transactional outbox, persisted pending batch, or downstream processor.

[planned-system-architecture.md](../../../planned-system-architecture.md) is marked `design-in-progress`. Its “IMPLEMENTED” sections are useful summaries, but future-tense service topology is not evidence of current runtime behavior.

## Current request path

```text
Dashboard Simulator
  -> synchronous POST /batch with complete Pricing Batch
  -> BatchController
  -> in-process Pricing Engine
  -> Pricing Configuration reads from PostgreSQL
  -> synchronous BatchResult response
```

## Planned request path

```text
Mock Account Processor
  -> persist account batch
  -> HTTP work-available wake-up
  -> separate Pricing Engine discovers pending work
  -> persist recommendations and outbox state
  -> HTTP work-available wake-up
  -> Mock Transaction Processor discovers pending recommendations
```

The planned wake-up contains no `batchId`; PostgreSQL processing state is the durable source of work. Duplicate notifications must be harmless. Exact endpoints, storage schema, chunk size, Pricing Decision persistence details, and complete idempotency behavior still require implementation-level decisions where the existing documents leave them open.

## Scope check for new work

Before implementing a feature described in architecture prose, locate its endpoint, model, migration, and test in current source. If they do not exist, treat the work as a new planned capability rather than an extension of an existing runtime path.

