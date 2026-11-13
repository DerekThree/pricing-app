# Mock Account Processor design

Confirmed design. This document records decisions from the design interview.

## Scope

The Mock Account Processor accepts and persists simulated Pricing Batches and notifies the
Pricing Engine that work may be available. The Mock Transaction Processor and Pricing Engine
processing are outside this design.

The Account Store uses a separate PostgreSQL database from the Pricing Store.

## Capacity and database access

Support submissions containing up to 100,000 accounts by default. Operators configure the
account-count limit with `BATCH_MAX_ACCOUNTS` before starting the server, without changing the
submission contract. Reject submissions exceeding the configured limit before persisting the
batch, with HTTP `400`, code `INVALID_BATCH`, and a message giving the limit and submitted count.

Flyway runs inside the server using the same database login and role as normal application
connections, following the existing backend's single-role configuration. This shared role has
the required read and insert permissions, schema and sequence access, and schema-changing
permissions for migrations. Database URLs and credentials are supplied through configuration.

## Submission

The Dashboard submits a complete Pricing Batch. Existing submission and evaluation validation
boundaries remain defined in [Validations](Validations.md).

- Persist all accounts, attributes, fee requests, and the outbox row in one transaction.
- Return HTTP `202 Accepted` after commit, with the accepted `batchId` and an acceptance message.
- Acknowledge acceptance independently of HTTP wake-up delivery.
- Reject any previously accepted `batchId`, regardless of submitted content, with HTTP `409`,
  code `BATCH_ALREADY_ACCEPTED`, and a descriptive message including the Batch ID. Preserve the
  accepted outbox (including `processed`), accounts, attributes, and Fee Requests unchanged.
- Enforce batch identity with the outbox primary key so concurrent submissions cannot both commit.
- Preserve `pricingDate` on each submitted account. There is no batch-level date field.

## Account Store

| Table | Contents |
| --- | --- |
| Outbox | The batch table: one row per batch with `batchId`, `processed` (initially `false`), and nullable `error` for Pricing Engine evaluation failures; no date. |
| Accounts | One row per submitted account, including its Pricing Date, associated with its batch. |
| Account attributes | One row per submitted attribute, associated with its account. |
| Fee requests | One row per submitted Fee Request, associated with its account. |

Account numbers must be unique within a batch. Submitted Fee Request IDs and attribute
codes must be unique within an account. Attribute-code uniqueness is a design requirement
but is not currently enforced by the database migrations.

Every account retains its submitted Pricing Date, which can differ between accounts in a
batch. Submitted attribute values retain their scalar type: strings map to `String`, numbers
to `BigDecimal`, and booleans to `Boolean`, using the existing
[scalar conversion semantics](../pricing-backend/src/main/java/com/pricing/backend/config/AccountAttributeValueDeserializer.java).
A transaction amount may be omitted, but an explicitly null supplied amount is rejected
by request validation before persistence. Persistence does not guarantee the submitted
order of accounts, attributes, or fee requests.

## Notification delivery

After commit, send the existing generic HTTP wake-up signal without `batchId`.

The Mock Server sends an empty HTTP `POST` to the configured Pricing Engine endpoint.
Delivery runs asynchronously after commit, so the submission response does not wait for the
consumer or retries. A `2xx` response completes delivery; other statuses, connection errors, and
timeouts consume attempts. Connection and response-read timeouts and the delay between failed
attempts are configurable; see the [Mock Server configuration](../pricing-mock-server/README.md).

The outbox stores `batch_id`, `processed`, and nullable `error`. The Pricing Engine writes
`error` when a non-recoverable evaluation failure occurs; batches with an error are excluded
from its pending-work selection. Neither a Pricing Date nor notification-delivery state is
persisted in this table. In particular, `error` does not track HTTP wake-up failures.
Retry failed delivery in memory up to a configured attempt limit, defaulting to three total
attempts: one initial attempt and at most two retries. Exhausting that limit leaves
the accepted batch stored and stops that retry sequence. On startup or restart, send a wake-up
when outbox rows with `processed=false` exist. Duplicate wake-ups are allowed. Successful delivery
does not change `processed`.

How the Pricing Engine processes a batch or changes `processed` is outside this design.

## HTTP contract

Use `POST /api/v1/mock/acc/batch` on the Mock Server under its separately owned OpenAPI contract.

| Situation | HTTP status | Response |
| --- | --- | --- |
| Batch committed | `202` | `batchId` and an acceptance `message`. |
| Previously accepted batch ID | `409` | `code=BATCH_ALREADY_ACCEPTED` and a descriptive `message`. |
| Invalid submission, including account-count limit | `400` | `code=INVALID_BATCH` and a descriptive `message`. |
| Account Store unavailable | `503` | `code=ACCOUNT_STORE_UNAVAILABLE` and a descriptive `message`. |

Pricing Engine notification failure does not change an already committed submission's acceptance.

## Relational schema

The implemented Account Store tables, columns, types, keys, constraints, indexes,
PostgreSQL-only triggers, grants, and migration history are documented in the
[Account Store database schema](DB%20Schemas/account-store-schema.md).
The Flyway migrations are authoritative for database-enforced constraints;
this design document describes intended processing behavior.

## Configuration values

Database connection details, HTTP wake-up URL, HTTP timeout, retry delays, attempt limit, and
account-count limit are configuration values. Concrete timeout and delay defaults can be tuned
during implementation without changing the agreed bounded retry policy.

## Related architecture

The broader flow is described in [Simulator Architecture](simulator-architecture.md) and
[System Architecture](system-architecture.md).

