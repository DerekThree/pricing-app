# Mock Account Processor design

Confirmed design. This document records decisions from the design interview.

## Scope

The Mock Account Processor accepts and persists simulated Pricing Batches and notifies the
Pricing Engine that work may be available. The Mock Transaction Processor and Pricing Engine
processing are outside this design.

The Account Store uses a separate PostgreSQL database from Pricing Configuration.

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
- Submit the simulator's Application Date once as batch-level `pricingDate`, shared by all accounts.

## Account Store

| Table | Contents |
| --- | --- |
| Outbox | The batch table: one row per batch with `batchId`, Application Date, and `processed`, initially `false`. |
| Accounts | One row per submitted account, associated with its batch. |
| Account attributes | One row per submitted attribute, associated with its account. |
| Fee requests | One row per submitted Fee Request, associated with its account. |

Accounts, Account Attributes, and Fee Requests use generated bigint identity primary keys.
Account numbers are unique within a batch. Submitted Fee Request IDs are unique within an account;
Fee Requests do not use a composite primary key.
Attribute codes are unique within an account, enforced by a database unique constraint on
`(account_id, code)`.

Persistence does not guarantee the submitted order of accounts, attributes, or fee requests.

## Notification delivery

After commit, send the existing generic HTTP wake-up signal without `batchId`.

The Mock Server sends an empty HTTP `POST` to the configured Pricing Engine endpoint.
Delivery runs asynchronously after commit, so the submission response does not wait for the
consumer or retries. A `2xx` response completes delivery; other statuses, connection errors, and
timeouts consume attempts. Connection and response-read timeouts and the delay between failed
attempts are configurable; see the [Mock Server configuration](../pricing-mock-server/README.md).

The outbox stores `batch_id`, `pricing_date`, and `processed`; notification-delivery state is not
persisted.
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

SQL column names use snake case; API field names retain their existing camel case.
The generated `id` primary key identifies each Account, Account Attribute, and Fee Request row.
Submitted Account Numbers are unique within a batch; submitted Fee Request IDs are unique within
an account; Attribute codes are unique within an account.

### Outbox

- `batch_id`: UUID primary key, corresponding to the submitted `batchId`.
- `pricing_date`: non-null date containing the batch's Application Date.
- `processed`: non-null boolean, initially `false`.

### Accounts

- `id`: generated bigint identity primary key.
- `batch_id`: UUID foreign key to Outbox.
- `account_number`, `product_code`, `branch_code`: strings using the existing API code limits.
- Unique constraint on `(batch_id, account_number)`.

### Account attributes

- `id`: generated bigint identity primary key.
- `account_id`: bigint foreign key to Accounts.
- `code`: string using the existing API code limits.
- `value`: non-null JSONB containing one string, number, or boolean scalar.
- Unique constraint on `(account_id, code)`.
- Check constraint: `jsonb_typeof(value) IN ('string', 'number', 'boolean')`.
  Objects, arrays, and JSON null are rejected; the non-null constraint also rejects SQL null.

Preserve the submitted scalar type using the existing
[scalar conversion semantics](../pricing-backend/src/main/java/com/pricing/backend/config/AccountAttributeValueDeserializer.java):
strings map to `String`, numbers to `BigDecimal`, and booleans to `Boolean`. Reading JSONB needs
a persistence adapter; the existing deserializer handles HTTP input. No separate type column is
needed because the JSONB value retains its scalar type.

### Fee requests

- `id`: generated bigint identity primary key.
- `account_id`: bigint foreign key to Accounts.
- `fee_request_id`: bigint corresponding to the submitted `feeRequestId`.
- Unique constraint on `(account_id, fee_request_id)`; no composite primary key.
- `code`: string using the existing API code limits.
- `transaction_amount`: optional numeric value, nonnegative and in increments of `0.01`.

Required request values are non-null in storage. An absent transaction amount is nullable.
Existing request validation rejects an explicitly null supplied transaction amount before
persistence.

## Configuration values

Database connection details, HTTP wake-up URL, HTTP timeout, retry delays, attempt limit, and
account-count limit are configuration values. Concrete timeout and delay defaults can be tuned
during implementation without changing the agreed bounded retry policy.

## Related architecture

The broader flow is described in [Simulator Architecture](simulator-architecture.md) and
[System Architecture](system-architecture.md).

