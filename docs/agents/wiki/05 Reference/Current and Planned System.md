---
status: current
verified: 2026-08-29
tags:
  - reference
  - roadmap
---

# Current and planned system

The repository contains implemented configuration CRUD, durable Mock Account Processor acceptance,
and standalone Pricing Engine processing triggered by startup and HTTP wake-ups. Each instance
admits parallel workers up to `ENGINE_MAX_WORKERS` (default `3`). Workers claim Account Outbox rows
with `processed = false AND error IS NULL` using `FOR UPDATE SKIP LOCKED`, so multiple instances
can process different batches. A worker holds its Account transaction through the separate local
Recommendation Store commit, then marks the source processed and commits its claim. Every finishing
worker releases its slot and triggers coordinated discovery. The Backend synchronous batch endpoint is
removed. The engine sends post-commit Transaction Processor wake-ups with bounded retries and
startup recovery for unprocessed recommendations. Temporary database operations retry with bounded
attempts and delay. After exhaustion, the affected worker retains its slot and checks the unavailable
store's connectivity periodically. Other workers continue within the cap; wake-ups at capacity are
ignored. Recovery stores each worker's retained result unchanged and finishes its known pending source
completion without recalculation. Healthy idle processing does not poll. Before evaluation, an existing
Recommendation Outbox row allows the engine to repair the Account Outbox processed flag without
recalculation. Storage retries use duplicate batch primary-key errors to recognize committed output.
Results and Recommendation Outbox state are preserved; startup reevaluates only uncommitted output.
Unexpected non-temporary evaluation exceptions are logged and committed as JSON `type`, nullable
`message`, and `stackTrace` in Account Outbox `error`, leaving `processed = false`. The worker
releases its claim and slot and triggers discovery while other workers continue. Errors exclude
batches across restarts until manually cleared to SQL `NULL`; the next startup, wake-up, or
completion-triggered scan can then process them. Unsaved errors retain their worker slot through
Account Store recovery. A valid claim saves the retained error; a lost transaction reclaims only
the same eligible batch. A competing owner or ineligible row discards it. Already committed
recommendations switch recovery to source completion without recalculation or resubmission.

| Capability | Current source | Planned or decided direction |
|---|---|---|
| Pricing Configuration | Implemented in the Spring Boot backend and PostgreSQL | Remains authoritative in the pricing backend |
| Dashboard | Implemented React Router SPA | Major dashboard convenience expansion is not the current architectural priority |
| Simulator | Backend date/options; Mock Account Processor `POST /api/v1/mock/acc/batch` with HTTP 202 acceptance | Completed asynchronous pricing results remain future work |
| Pricing Engine | Standalone evaluator; capped parallel workers across multiple instances | No global FIFO order |
| Configuration loading | Candidate Pricing Plans filtered by submitted Pricing Dates in PostgreSQL; remaining evaluation in Java | Evaluation boundary accepted by ADR 0004 |
| Pricing Batch storage | Mock Account Processor persists account records and Account Outbox in PostgreSQL | Engine reads accepted accounts with their individual Pricing Dates |
| Batch trigger | Startup recovery completes before the HTTP listener accepts payload-free `POST /api/v1/work-available`; empty HTTP 202 | No queued wake-ups or healthy idle polling |
| Pricing Decisions | Relational recommendations and one outbox row; post-commit HTTP wake-ups | Transaction Processor consumes persisted output |
| Outbox and recovery | Transactional Account claims with skip-locked discovery; atomic recommendation/outbox persistence; source completion after output commit; worker-local result, completion, and unsaved-error recovery; uniqueness preserves committed output | ADR 0008 recovery implemented |
| Transaction Processor | Not implemented | Mock external consumer of persisted recommendations |
| Rates | No current route, entity, migration, or dashboard screen | Mentioned in historical/planned material but not defined as a current domain capability |

## Accepted decisions versus implementation

[ADR 0004](../../../ADR/0004-choose-pricing-engine-evaluation-location.md) is both accepted and reflected in the current prototype: SQL filters candidate Pricing Plans, then Java owns exact resolution, validation, eligibility, calculation, and statuses.

[ADR 0005](../../../ADR/0005-Use-HTTP-for-batch-ready-notifications.md) defines the notification
boundaries. The Account Processor persists pending work and sends generic wake-ups. The engine
discovers work on startup and wake-ups and persists recommendations with an outbox using capped
parallel workers. Completion-triggered discovery and wake-ups overlapping an empty scan are
coordinated so eligible work is not stranded.
The engine sends downstream wake-ups after recommendation commit, independently of source completion.
Delivery follows the Account Store convention: HTTP acknowledgement leaves the outbox unchanged,
and startup sends a wake-up when unprocessed recommendations exist.
The Transaction Processor remains future work.

[planned-system-architecture.md](../../../planned-system-architecture.md) is marked `design-in-progress`. Its “IMPLEMENTED” sections are useful summaries, but future-tense service topology is not evidence of current runtime behavior.

## Current request path

```text
Dashboard Simulator
  -> Backend for configuration, Simulator options, and Application Date
  -> Mock Account Processor POST /api/v1/mock/acc/batch with account-level pricingDate
  -> durable batch acceptance
  -> HTTP 202 batchId and message
  -> locked Simulator until Reset
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

Wake-ups contain no `batchId`; PostgreSQL processing state is the durable source of work. The
engine's wake-up endpoint and downstream wake-up client are implemented. Duplicate incoming
wake-ups discover work when capacity is available; startup recovery resends downstream wake-ups while recommendations
remain unprocessed. Interrupted-completion recovery is implemented. The Transaction Processor
remains future work.

## Scope check for new work

Before implementing a feature described in architecture prose, locate its endpoint, model, migration, and test in current source. If they do not exist, treat the work as a new planned capability rather than an extension of an existing runtime path.

