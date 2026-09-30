# Simulator Architecture

Status: designed but unimplemented

This document describes the current Batch Simulator integration and its intended future architecture.
The canonical name for the evaluator is **Pricing Engine**; a **Pricing Batch** is a caller-identified
collection of accounts submitted for evaluation.

## Current prototype

```text
Dashboard -> HTTP POST /batch -> Pricing Backend -> in-process prototype
          <- complete result in the same HTTP response <-
```

The Dashboard currently sends the batch to `pricing-backend`. The backend invokes its prototype
Pricing Engine and returns the correlated result synchronously. This transport is temporary and does
not determine the future batch architecture.

## Future architecture

```text
Dashboard -> Pricing Backend: Pricing Configuration APIs
Dashboard -> Mock Account Processor: simulated Pricing Batch

Mock Account Processor -> Account Store [PostgreSQL]: persist batch
Mock Account Processor -> Account Outbox [PostgreSQL]: persist work-available outbox row atomically
Mock Account Processor -> Pricing Engine: HTTP work-available wake-up

Pricing Engine -> Account Store [PostgreSQL]: query unprocessed batches
Pricing Engine -> Recommendation Store [PostgreSQL]: persist output
Pricing Engine -> Recommendation Outbox [PostgreSQL]: persist work-available outbox row atomically
Pricing Engine -> Mock Transaction Processor: HTTP work-available wake-up

Mock Transaction Processor -> Recommendation Store [PostgreSQL]: query unprocessed output
Mock Transaction Processor -> Dashboard: WebSocket Batch Result
```

| Application | Responsibility |
| --- | --- |
| Pricing Dashboard | Manages Pricing Configuration and provides the Batch Simulator. |
| Pricing Backend | Owns the real Pricing Configuration HTTP APIs. |
| Pricing Engine | Runs separately, processes persisted account batches, reads Pricing Configuration, and persists transaction recommendations. |
| Mock Account Processor | Simulates the external Account Processor, persists account batches, and notifies the Pricing Engine that work may be available. |
| Mock Transaction Processor | Simulates the external Transaction Processor, reads persisted recommendations, processes them, and reports the simulated result to the Dashboard. |

The two mocks may initially run as separate components in one `mock-processors` application. That
application remains separate from both `pricing-backend` and the Pricing Engine. All applications may
run on one development machine while remaining separate processes with separate network addresses.

The Account Processor and Transaction Processor are outside the pricing system. The simulator mocks
those boundaries, but they should behave as if they were independent external systems.

## Processing flow

1. The Dashboard loads Simulator options from the Pricing Backend.
2. It submits a simulated Pricing Batch to the Mock Account Processor over HTTP.
3. The Mock Account Processor persists the account batch in PostgreSQL.
4. In the same database transaction, the Mock Account Processor persists the outbox row indicating
   that account work may be available.
5. After persistence succeeds, the Mock Account Processor sends an HTTP wake-up notification to the
   Pricing Engine.
6. The wake-up notification does **not** contain `batchId`. It is only a generic signal that new work
   may be available.
7. The Pricing Engine queries PostgreSQL for account batches that are still unprocessed and evaluates
   the available work using Pricing Configuration from PostgreSQL.
8. The Pricing Engine persists the resulting transaction recommendations in PostgreSQL.
9. In the same transaction as the persisted recommendation batch/state, the Pricing Engine persists
   the corresponding outbox row.
10. After persistence succeeds, the Pricing Engine sends an HTTP wake-up notification to the Mock
    Transaction Processor.
11. The Mock Transaction Processor queries the Recommendation Store for unprocessed recommendation
    work and processes it.
12. The Mock Transaction Processor sends the resulting Batch Result to the Dashboard over WebSocket.
13. The Dashboard correlates the displayed result using `batchId`, `accountNumber`, and
    `feeRequestId`.

The HTTP notifications are **wake-up signals**, not the durable representation of work. PostgreSQL is
the durable source of pending work on both notification boundaries.

On startup or restart, a consuming service queries PostgreSQL for ready/unprocessed batches so that
work remains discoverable even when the service was unavailable when the original HTTP notification
was attempted.

## Notification and recovery model

There are two work-available notification boundaries:

1. **Mock Account Processor -> Pricing Engine:** account work may be available.
2. **Pricing Engine -> Mock Transaction Processor:** recommendation work may be available.

Both boundaries use HTTP.

The producing service owns the outbox associated with the work it persists.

### One outbox row per batch

The outbox is **not an append-only event log**. There is exactly one outbox row for each batch.
`batchId` is the primary key of the outbox row.

The row is inserted once and its notification status is updated over time. A second outbox row for the
same batch is never created.

Conceptually:

```text
batchId = B123 | status = PENDING
```

and after successful publication:

```text
batchId = B123 | status = SENT
```

If a producer successfully sends the HTTP wake-up notification but crashes before updating the row
from `PENDING` to `SENT`, restart recovery may send the same wake-up again. That duplicate wake-up is
acceptable because the HTTP request contains no business work and the consumer simply re-checks the
database.

### Atomicity within the producer-owned database

The durable business result produced by a service and the outbox row for that batch are written
atomically in the same PostgreSQL transaction **within the database owned by that result**.

For Pricing Engine output, recommendation-batch persistence, recommendation records, and insertion of
the recommendation outbox row for the same `batchId` occur atomically in the Recommendation Store.

The architecture should not require the Account Store and Recommendation Store to remain in the same
physical database. They may be separated into different databases in the future.

If they are separated, updating the source Account Batch status and writing the Recommendation Batch
cannot be one local database transaction. Idempotency across that boundary is instead based on the
identity of the batch:

- the recommendation outbox has exactly one row for each Pricing Batch;
- `batchId` is the primary key of that outbox row;
- recommendation persistence and insertion of the outbox row occur in the same Recommendation Store
  transaction;
- if the Pricing Engine sees the source batch again after a crash or failed source-status update, the
  existing outbox row for that `batchId` proves that the recommendation result was already committed;
- a duplicate attempt cannot commit another recommendation result because it cannot insert another
  outbox row with the same primary key;
- the Pricing Engine can then repair/update the source batch status rather than generate a second
  committed set of recommendations.

This also protects against two Pricing Engine instances attempting to complete the same batch
concurrently: only one transaction can successfully insert the outbox row for that `batchId`; the
other transaction is rejected/rolled back.

Normal producer behavior:

- persist the producer-owned business result and the one outbox row for the batch atomically;
- after persistence succeeds, publish the HTTP wake-up notification;
- update the outbox row status to indicate successful publication.

Producer recovery behavior:

- on startup or restart, scan the outbox for rows whose status still requires publication;
- republish those wake-up notifications.

Consumer recovery behavior:

- on startup or restart, query PostgreSQL for ready/unprocessed batches;
- process work that is still pending;
- use `batchId` to recognize a batch whose downstream result has already been persisted.

Continuous database polling solely for crash recovery is not part of the current design.

A separate CDC process, standalone outbox publisher, Kafka, DynamoDB Streams, or Lambda notification
path is not part of the current design.

## Duplicate delivery and idempotency

Duplicate HTTP wake-up notifications are possible. For example, a producer can successfully send a
wake-up notification and then fail before updating the batch's outbox row from `PENDING` to `SENT`.
On restart, the producer sees the still-pending row and sends the wake-up notification again.

The duplicate notification itself is harmless because the consumer does not process business work
contained in the HTTP request. It simply queries PostgreSQL for work that is still unprocessed.

For Pricing Engine processing, `batchId` is the idempotency key across retries and any future
Account-Store/Recommendation-Store database split. The recommendation outbox contains exactly one row
per Pricing Batch, with `batchId` as its primary key.

Recommendation persistence and insertion of that outbox row happen in the same Recommendation Store
transaction. If the same batch is processed again, the second transaction cannot insert another
outbox row with the same `batchId`; the conflict causes that duplicate recommendation transaction to
be rejected/rolled back. The existing outbox row therefore proves that the recommendation result for
that batch was already committed.

If the source Account Batch is encountered again because its status update failed after the
Recommendation Store transaction committed, the Pricing Engine must not create another committed set
of recommendations. It can instead repair the source-batch status.

The Transaction Processor is outside the pricing-system boundary. Preventing duplicate posting of
actual financial transactions is therefore not a responsibility of the pricing system. The simulator's
Mock Transaction Processor exists only to exercise the external boundary and display the resulting
recommendations.

## Recommendation Store

Transaction recommendations are stored in **PostgreSQL**.

The Recommendation Store is purpose-defined for the pricing workflow and is separate in purpose from
Pricing Configuration, even if both use PostgreSQL. Recommendation data is generated by the Pricing
Engine and is expected to be primarily append-oriented / immutable after calculation.

The Mock Transaction Processor may read recommendations from this purpose-defined store/read model.
That access is an intentional recommendation-data contract; it is not permission for the Transaction
Processor to depend arbitrarily on unrelated internal Pricing Engine persistence structures.

The recommendation batch, its recommendation records, and the corresponding outbox row can therefore
be persisted atomically in one database transaction.

## Contracts and generated clients

The Dashboard consumes three provider-owned contracts:

| Provider | Contract | Dashboard artifact |
| --- | --- | --- |
| Pricing Backend | OpenAPI | Orval-generated Backend HTTP client and models. |
| Mock Account Processor | OpenAPI | Separate Orval-generated Account Processor client and models. |
| Mock Transaction Processor | AsyncAPI with versioned JSON Schema | Generated TypeScript message models. |

The two Orval projects use separate output directories so their operations and model names cannot
collide. Dashboard code explicitly imports the client belonging to the server it calls.

The browser WebSocket connection wrapper remains handwritten using the native `WebSocket` API. It
uses the generated message model, parses incoming data as unknown, and validates it against the
versioned schema before displaying it.

The Dashboard needs independent environment-specific addresses for:

```text
PRICING_BACKEND_HTTP_URL
ACCOUNT_PROCESSOR_HTTP_URL
TRANSACTION_PROCESSOR_WEBSOCKET_URL
```

The internal work-available endpoints between the Mock Account Processor, Pricing Engine, and Mock
Transaction Processor use separate provider-owned HTTP contracts. They carry only the wake-up signal,
not the persisted batch contents.

## Decided boundaries and infrastructure

- The future Pricing Engine runs separately from `pricing-backend`.
- Neither external-system mock belongs in `pricing-backend`.
- Both mocks may initially share one separately deployable Mock Processors application.
- The Pricing Engine does not run inside the Mock Processors application.
- The Account Processor and Transaction Processor remain external-system boundaries from the pricing
  system's perspective.
- Account batches are persisted in PostgreSQL before the Pricing Engine is notified.
- Transaction recommendations are persisted in PostgreSQL before the Transaction Processor is notified.
- Both work-available notification boundaries use HTTP.
- HTTP notifications are generic wake-up signals and do not contain `batchId`.
- PostgreSQL, not HTTP, is the durable source of pending work.
- Producers use a transactional outbox so their persisted result and the corresponding notification
  intent are committed atomically within the producer-owned database.
- The outbox contains exactly one row per batch; `batchId` is the outbox primary key and publication
  state is updated on that row rather than represented by additional rows.
- Pricing-batch idempotency is enforced by the one-row-per-batch outbox: `batchId` is its primary
  key, and recommendation persistence plus outbox insertion occur in one Recommendation Store transaction.
- Account Store and Recommendation Store may be separated into different physical databases in the
  future; the architecture does not depend on a cross-database transaction.
- If the same Account Batch is encountered again after its recommendation result was already committed,
  the existing outbox row for `batchId` prevents a second recommendation transaction from committing
  and allows the source status to be repaired.
- The service that persists the work owns publishing and recovery of its corresponding outbox row.
- Consumers query PostgreSQL for unprocessed work on startup/restart.
- Duplicate wake-up delivery is allowed and must be harmless.
- Actual transaction-posting idempotency is outside the pricing-system boundary because the
  Transaction Processor is an external system represented only by a mock in the simulator.
- Each HTTP provider owns its OpenAPI contract and generated-client namespace.
- WebSocket messages have a separate asynchronous contract and versioned schema.
- Kafka, DynamoDB, CDC, Lambda, and a standalone outbox-publisher service are not part of the current
  design.

## Open decisions

- Submission acknowledgement details between the Dashboard and Mock Account Processor.
- Exact initial physical PostgreSQL database/schema topology. The Account Store and Recommendation
  Store may share infrastructure initially but must remain separable into different databases.
- Exact Account Store and Recommendation Store schemas beyond the decided one-outbox-row-per-batch
  model and `batchId` outbox primary-key invariant.
- WebSocket message granularity, authentication, reconnection, and missed-message recovery.
- Whether the two mocks ever need separate deployments.
