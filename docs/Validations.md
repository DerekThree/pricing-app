# For agents
- Use DB constraints whenever you can
- Disable inputs to prevent the user from entering invalid values whenever you can
- For validations that are not present in the front end, create a descriptive error message
- return appropriate error code
- Do not use business logic layer to validate things that are already validated by Jakarta or DB
- If using service layer for validations, put the code in the service's validator
- Look at how similar validations have been implemented and follow established conventions
- Update validation matrix when updating validations

# Validation Matrix

| Validation | UI | API contract | Backend logic | Status and Error message | DB |
|---|---|---|---|---|---|
| Record codes are 1–25 uppercase letters/digits | Yes | Yes | No | 400 — `branchCode must match "^[A-Z0-9]{1,25}$"` | No — only length/not-null/unique are enforced |
| Record names are non-empty and at most 100 characters | Yes | Yes | No | 400 — `branchName size must be between 1 and 100` | Partial — not-null and maximum length; blank strings are valid |
| Branch state is two uppercase letters | Yes | Yes | No | 400 — `state must match "^[A-Z]{2}$"` | No — only length is enforced |
| Branch ZIP code is five digits | Yes | Yes | No | 400 — `zipCode must match "^[0-9]{5}$"` | No — only length is enforced |
| Product type, fee type, attribute type, and reason operator are valid enum values | Yes | Yes | No | 400 — `Request body is malformed` | Yes — check constraints |
| Record codes are unique | No | No | No | 409 — `A record with the same code already exists` | Yes — unique constraint |
| A region branch exists | Yes | No | No | 409 — `The request violates a record relationship` | Yes — FK |
| A branch, state, or ZIP belongs to at most one region | Yes | No | No | 409 — `A record with the same code already exists` | Yes — unique constraints |
| A pricing plan product exists | Yes | No | No | 409 — `The request violates a record relationship` | Yes — FK |
| A pricing plan region exists | Yes | No | No | 409 — `The request violates a record relationship` | Yes — FK |
| Active Through is on or after Active From | Yes | No | No | 400 — `Active Through must be on or after Active From` | Yes — check constraint |
| Pricing-plan active periods do not overlap for the same Product and Region | Yes | No | No | 400 — `Pricing plan active period overlaps an existing pricing plan` | Yes — PostgreSQL exclusion constraint |
| A new pricing plan does not start before the application date | Yes | No | Yes | 400 — `activeFrom must be on or after the application current date` | No |
| An active plan can change only its name and Active Through | Yes | No | Yes | 400 — `Only planName and activeThrough can be updated for an active pricing plan` | No |
| A past plan can change only its name | Yes | No | Yes | 400 — `Only planName can be updated for a past pricing plan` | No |
| An active plan cannot end before the application date | Yes | No | Yes | 400 — `activeThrough must be on or after the application current date` | No |
| An active pricing plan cannot be deleted | No | No | Yes | 400 — `Active pricing plans cannot be deleted` | No |
| A pricing-plan fee exists | Yes | No | No | 409 — `The request violates a record relationship` | Yes — FK |
| A fee is valid for the selected product type | Yes | No | Yes | 400 — `Fee with id <id> cannot be used for this product type` | No |
| A pricing plan does not contain the same fee twice | Yes | No | No | 400 — `A pricing plan cannot contain the same fee twice` | Yes — composite primary key |
| A pricing-plan fee amount is non-negative | Yes | Yes | No | 400 — `fees[<index>].amount must be greater than or equal to 0` | Yes — check constraint |
| A pricing-plan eligibility reason exists | Yes | No | No | 409 — `The request violates a record relationship` | Yes — FK |
| A pricing-plan eligibility reason is valid for the selected product type | No | No | Yes | 400 — `Eligibility reason with code <code> cannot be used for this product type` | No |
| A fee does not contain the same eligibility reason twice | Yes | No | No | 400 — `A fee cannot contain the same eligibility reason twice` | Yes — composite primary key |
| A Fee applies to at least one Product Type | Yes | Yes | No | 400 — `Applicable Product Types must contain at least one item` | No — child rows cannot require at least one row |
| A fee does not contain the same product type twice | Yes | No | No | 400 — `A fee cannot contain the same product type twice` | Yes — unique constraint |
| An Account Attribute applies to at least one Product Type | Yes | Yes | No | 400 — `Applicable Product Types must contain at least one item` | No — child rows cannot require at least one row |
| An Account Attribute does not contain the same Product Type twice | Yes | No | No | 400 — `An account attribute cannot contain the same product type twice` | Yes — unique constraint |
| Selected Eligibility Reason Attributes share at least one Product Type | No | No | Yes | 400 — `Applicable Product Types must contain at least one item` | No |
| A Fee definition cannot be updated when used by a Pricing Plan | No | No | Yes | 409 — `This fee is used by pricing plan with code <code>. Please update the pricing plan first.` | No |
| Only an Eligibility Reason's name can be updated when used by a Pricing Plan | No | No | Yes | 409 — `This eligibility reason is used by pricing plan with code <code>. Please update the pricing plan first.` | No |
| Only an Account Attribute's name can be updated when used by an Eligibility Reason | No | No | Yes | 409 — `This account attribute is used by eligibility reason with code <code>. Please update the eligibility reason first.` | No |
| A reason condition references an existing account attribute | Yes | No | No | 409 — `The request violates a record relationship` | Yes — FK |
| A text condition uses only `=` or `<>`; a boolean condition uses `=` | Yes | No | No | N/A — No error; an invalid type-specific operator is accepted | No |
| A condition value matches its attribute type | Yes | No | Yes | 400 — `Condition value for account attribute <code> must be an integer` | No |
| A condition value is a string, number, or boolean | Yes | Yes | Yes | 400 — `Condition value must be a string, number, or boolean` | No |
| A Branch, Product, Region, Fee, Account Attribute, or Eligibility Reason cannot be deleted while referenced | No | No | Yes | 409 — `This <record> is used by <referencing record> with code <code>. Please update the <referencing record> first.` | Yes — restrictive FK |

## Mock Account Processor — Account Store

The provider-owned Mock Account Processor contract is `pricing-mock-server/openapi.yaml`.
The Backend synchronous batch endpoint has been removed. Submission validation belongs to the Mock Account Processor contract and its `BatchValidator`; pricing data
type compatibility and required-attribute checks remain Pricing Engine evaluation concerns.

Submission error messages include zero-based field paths, such as
`accounts[1].fees[0].transactionAmount`. Custom validation also includes the Account Number and,
where applicable, Fee Request ID and Fee code. Duplicate identities identify both record paths.
Malformed values retain the parser's field path; syntax errors include line and column when
available. Database constraint errors include PostgreSQL's table/column and key or failing-row
details when supplied; these describe stored values rather than submitted array positions.
The response remains `code` plus `message`. The table lists the reasons before variable context.

| Validation | UI | API contract | Backend logic | Status and Error message | DB |
| --- | --- | --- | --- | --- | --- |
| Submission shapes and collection items must be valid and non-null | No | Yes | Yes — null collection items | 400 — `INVALID_BATCH`, field validation, `Request body is malformed`, or descriptive null-item message | No |
| Required submission values and existing code formats/limits are preserved | No | Yes | No | 400 — `INVALID_BATCH`, descriptive validation message | Yes — required columns non-null; strings limited to 25 characters |
| Accounts per Pricing Batch must not exceed `BATCH_MAX_ACCOUNTS` (default `100000`) | No | Yes — runtime limit documented | Yes — `BatchValidator`, before persistence | 400 — `INVALID_BATCH`, `Pricing Batch exceeds the limit of <limit> accounts (<count> submitted).` | No — rejection leaves no partial batch |
| Previously accepted Batch IDs are rejected regardless of payload differences | No | Yes | Yes — insert-only persistence; centralized constraint handling | 409 — `BATCH_ALREADY_ACCEPTED`, `This Pricing Batch has already been accepted` with the Batch ID | Yes — `batch_outbox` primary key; rejected transactions leave all accepted rows unchanged |
| Submitted Fee Request IDs are unique within an Account | No | No | Yes | 400 — `INVALID_BATCH`, `Fee Request IDs must be unique within an account` | Yes — unique `(account_id, fee_request_id)`; generated bigint `id` is the primary key |
| Attribute values retain string, number, or boolean scalar type; repeated codes remain separate rows | No | Yes | No | 400 — `INVALID_BATCH` for malformed values; persisted scalar-check violations return `Account Attribute value must be a string, number, or boolean` | Yes — non-null JSONB scalar check; no uniqueness on attribute code |
| A present transaction amount is non-null, nonnegative, and uses increments of 0.01; an absent amount is SQL null | No | Yes | Yes | 400 — `INVALID_BATCH`, generated null/minimum validation or `Transaction Amount must use increments of 0.01`; persisted monetary-check violations return `Transaction Amount must be nonnegative and use increments of 0.01` | Yes — nullable unrestricted `numeric` with nonnegative and increment checks |
| Accounts reference a batch; attributes and Fee Requests reference an account | No | No | No | 400 — `INVALID_BATCH`, `The request violates a database constraint` | Yes — foreign keys |
| Acceptance requires atomic commit of all accounts, attributes, Fee Requests, and the Batch Outbox | No | Yes | Yes | 202 after commit; 503 — `ACCOUNT_STORE_UNAVAILABLE` when the store is unavailable | Yes — one transaction; rollback leaves no partial batch |
| Account Store records and batch identities remain immutable | No | No | No | Inserts and permitted outbox processing updates succeed; other mutations are rejected | Yes — Flyway triggers reject UPDATE, DELETE, and TRUNCATE on `accounts`, `account_attributes`, and `fee_requests`; reject deletion, truncation, and `batch_id` changes on `batch_outbox` for all roles; retain table-wide outbox UPDATE |
| Pricing Engine wake-ups advertise only committed work and carry no business payload or Batch ID | No | No | Yes — asynchronous post-commit empty HTTP POST; failed or rejected transactions do not notify | 202 remains accepted through delivery errors and bounded retry exhaustion | Accepted rows and `processed` remain unchanged; no delivery state is stored |

## Pricing Engine — Recommendation Store

The engine evaluates persisted accounts using each account's Pricing Date. It records expected
account and Fee Request failures as outcomes; it exposes no pricing HTTP operation in this ticket.

| Validation | UI | API contract | Engine logic | Outcome | DB |
| --- | --- | --- | --- | --- | --- |
| A required Batch Account Attribute occurs at most once | No | No | Yes | Stored account outcome `DUPLICATE_ATTRIBUTE`; no error message | No |
| A supplied required Batch Account Attribute matches its configured type | No | No | Yes | Stored account outcome `INVALID_ATTRIBUTE_TYPE`; no error message | No |
| Every required Batch Account Attribute is supplied | No | No | Yes | Stored account outcome `MISSING_ATTRIBUTE`; no error message | No |
| A persisted Eligibility Reason condition uses an operator supported by its configured Attribute type during Pricing Batch evaluation | No | No | Yes | Stored Fee Request outcome `ERROR`; no error message | Partial â€” the operator is constrained, but the operator-and-type combination is not |
| A Batch Account has an applicable Pricing Plan for its Product, Region, and Pricing Date | No | No | Yes | Stored account outcome `PLAN_NOT_FOUND`; no error message | No |
| One Recommendation Outbox row per batch identifier | No | No | Insert-only JPA persistence; a duplicate outbox primary-key error during storage identifies committed output | Preserve output and repair Account Outbox processing status; other constraint errors still fail | Yes — outbox batch identifier primary key; account recommendations reference the outbox |
| Recommendation batch, records, and outbox commit atomically | No | No | One local Recommendation Store transaction | A write failure leaves no partial output | Yes — transaction rollback |
| Recommendation records and batch identities remain immutable | No | No | No | Inserts and permitted outbox processing updates succeed; other mutations are rejected | Yes — Flyway triggers reject UPDATE, DELETE, and TRUNCATE on `account_recommendations`, `fee_request_recommendations`, and `recommendation_eligibility_reasons`; reject deletion, truncation, and `batch_id` changes on `recommendation_outbox` for all roles; retain table-wide outbox UPDATE |
| Each instance respects its worker cap | No | No | `ENGINE_MAX_WORKERS`, default `3`; calculating, retrying, and recovering workers occupy slots; every completion triggers coordinated discovery | Wake-ups at capacity are ignored; overlapping completions/wake-ups cannot exceed the cap or strand eligible work | No |
| Only eligible, unclaimed Account Outbox rows are processed | No | No | Claim `processed = false AND error IS NULL` with `FOR UPDATE SKIP LOCKED`; SQL NULL alone means no error | Processed, errored, and locked rows are skipped across instances | Nullable SQL text `error`; Account transaction retains the row lock during processing |
| Unexpected non-temporary evaluation exceptions exclude their batch | No | No | Log the exception and commit JSON `type`, nullable `message`, and `stackTrace` in Account Outbox `error` through the held claim transaction; leave `processed = false` | Release the claim and worker slot and trigger discovery; other workers continue; exclusion survives restart; clearing `error` to SQL NULL restores eligibility on startup, wake-up, or completion | Nullable SQL text `error`; temporary database failures retain bounded retries and connectivity recovery |
| Source completion follows recommendation commit | No | No | Mark processed and commit the held Account claim transaction after output save succeeds or its duplicate batch key identifies committed output; after claim loss, retry completion in a new Account transaction without reclaiming | Retain the completion ID and worker slot through bounded retries and five-second connectivity checks; do not recalculate or resubmit committed output; completion releases the slot and triggers discovery | Separate local Account and Recommendation Store transactions |
| Unsaved rule-engine errors survive temporary Account Store failures | No | No | Retain the exception and slot through bounded retries and connectivity recovery; save in a valid original claim or reclaim only the same eligible batch after transaction loss | Discard for another owner or an ineligible batch; committed recommendations switch to source-completion recovery without recalculation or resubmission; terminal outcomes release capacity and trigger discovery | Structured error commits with `processed = false` in the Account transaction |
| Restart recovery preserves committed recommendations | No | No | Before evaluation, check the Recommendation Outbox by batch ID regardless of its processed flag; repair the Account Outbox flag when output exists | Preserve result and Recommendation Outbox state despite changed pricing data; no recalculation of committed output | Separate Account and Recommendation Store transactions |
| Restart recovery recalculates output that never committed | No | No | Discover unprocessed durable account input on startup | No partial recommendations or durable calculation cache; evaluate again using pricing data captured on restart | Recommendation records and outbox commit atomically |
| Transaction Processor wake-ups advertise only committed output and carry no Batch ID or payload | No | No | Virtual thread starts after recommendation save commits, before source completion | Rollback sends no wake-up; source-completion failure does not suppress delivery | Recommendation rows and outbox commit atomically |
| Temporary database failures retry only the interrupted operation | No | No | Configured bounded attempts and delay; each affected worker retains its slot; exhaustion starts periodic connectivity checks of the unavailable store | Other workers may continue within the cap; checks stop after recovery and there is no healthy idle polling | Every storage attempt preserves the existing local transaction boundaries |
| Storage failures preserve completed calculations | No | No | Retain each worker's result and completion state through failures and exhaustion; resume storage unchanged after connectivity returns | Pricing data changes do not alter retained results; known pending source completion requires no recalculation; other workers may discover work | Recommendation records and outbox commit atomically |
| HTTP failures and timeouts preserve completed pricing | No | No | Bounded in-memory retries with configured attempts, delay, and HTTP timeout | Delivery stops after success or exhaustion; no recalculation or result changes | Successful or failed HTTP delivery leaves the existing outbox row unchanged |
| Startup wakes the Transaction Processor for unprocessed recommendations | No | No | Background startup recovery checks `processed=false` before account draining | Empty or processed-only stores send no wake-up; recovery does not block HTTP readiness; duplicate delivery preserves results | Existing outbox processing state remains authoritative |
| Engine readiness requires initialization of all three databases | No | No | Shared privileged login creates databases/logins and runs Flyway migrations and grants before HTTP startup | Initialization failure prevents `/openapi.yaml` readiness; pending processing and unavailable downstream services do not delay readiness | Runtime logins remain separate and cannot migrate schemas |
