# Choose where Pricing Engine evaluation executes

## Status

Implemented

## Context

The Pricing Engine starts work from an account-batch-ready notification that identifies a batch in a database. The notification does not carry the account records. The engine processes the persisted batch in bounded chunks. The notification mechanism and Pricing Decision persistence are separate decisions; this ADR evaluates where pricing behavior executes and how data crosses the database seam.

A logical Pricing Batch may contain approximately 100,000 accounts. Performance and consistency must therefore be evaluated per chunk rather than across the entire logical batch at once. The chunk size has not been selected.

Pricing Configuration consists of Products, Branches, Regions, Pricing Plans, Pricing Plan Fees, Eligibility Reasons, conditions, and Account Attribute definitions. It is expected to contain substantially fewer records than account batches. The pricing backend is the only writer of this configuration, and the Pricing Engine reads it. Whether account-batch data and Pricing Decisions use the same database as Pricing Configuration or a separate database remains open.

Every option must implement the same behavior: exact code lookup; Branch, then ZIP code, then state Region precedence; Product, Region, and Pricing Date Plan selection; required Account Attribute validation; typed condition comparison; AND within one Eligibility Reason and OR between Reasons; flat and percentage Fee calculation; and isolated account and Fee statuses. The choice in this ADR is where that behavior executes and how data crosses the database seam.

## Options Considered

### Evaluate all pricing behavior in Java

A batch worker reads a bounded chunk of persisted account records and passes engine-owned account models to the Pricing Engine, which owns the business logic. It derives configuration criteria from the chunk and calls an engine-owned `PricingConfigurationRepository`. A JPA adapter performs bulk reads and returns an immutable `PricingConfigurationSnapshot`. The snapshot contains Products and Branches keyed by code, Regions and their memberships, and candidate Pricing Plans containing their Fees, Eligibility Reasons, conditions, and Account Attribute definitions.

- **Benefits:**
  - Keeps Region resolution, Plan selection, validation, condition evaluation, status derivation, and monetary calculation together in one Java module.
  - Keeps the engine independent of PostgreSQL query language, stored-function deployment, JPA entities, and the account-batch-ready notification transport.
  - Supports fast TDD of real pricing behavior with an in-memory `PricingConfigurationRepository`; PostgreSQL tests are limited to the JPA adapter and database constraints.
  - Keeps typed values, date comparison, `BigDecimal` calculation, and impossible result combinations explicit in Java types.
  - Separates account-batch-ready notification handling and account-batch persistence from pricing rules.
- **Costs:**
  - Requires a mapping layer from persisted entities or projections into an additional immutable configuration representation.
  - Requires several bulk queries behind one repository call. They need a read-only `REPEATABLE_READ` transaction if one chunk must observe a single database snapshot.
  - Transfers Pricing Configuration from the database into the engine for every chunk unless cross-chunk caching is a part of the design.
  - Transfers each account chunk from its database into the application before evaluation.
  - Uses application heap and CPU to evaluate every account and Fee Request.
  - Does not automatically exploit PostgreSQL's set-based execution or query parallelism for the account calculations.

### Resolve configuration in SQL and evaluate decisions in Java

The caller supplies engine-owned account records for one Pricing Engine invocation. The Pricing
Configuration adapter uses their distinct Pricing Date to limit Pricing Plans to those active for the submitted date. Because batches contain only one pricing date, there is no need to fetch plans that were not active on that date. The number of Branches and Regions is much smaller than the number of
Pricing Plans, so database-side filtering is materially more valuable for Plans than for those
configuration records. Java receives immutable Pricing Configuration and performs Region and Fee resolution, Account Attribute validation, typed condition evaluation, waiver decisions, status mapping, and monetary calculation.

- **Benefits:**
  - Excludes Pricing Plans that were not active for the Pricing Date present in the batch before configuration is transferred to Java.
  - Uses the batch's Pricing Date to filter the configuration type with the largest expected record count.
  - Reduces configuration transfer and Java heap use without moving Account Attribute validation, condition evaluation, waiver decisions, status mapping, or monetary calculation into SQL.
  - Keeps dynamic type handling, Eligibility Reason semantics, failure isolation, and financial rounding in Java, where they are easier to express and unit-test.
  - Avoids adding database-side filtering for Fees, Branches, and Regions, whose record counts are expected to be much smaller than the number of Pricing Plans.
- **Costs:**
  - Splits Pricing Plan filtering between SQL and Java: SQL limits Plans by active period, while Java performs the remaining Plan selection and pricing behavior.
  - Requires an adapter query and mapping dedicated to filtering Pricing Plans by the batch's Pricing Date.
  - Requires PostgreSQL integration tests for active-period filtering in addition to Java pricing-rule tests.
  - May still transfer more Eligibility Reasons and Account Attribute definitions than evaluation needs because their value as database-side filters is not yet known.
  - Changes to Pricing Plan active-period semantics may require coordinated SQL and Java changes.

### Evaluate all pricing behavior in SQL

A native SQL query or PostgreSQL function accepts a batch or chunk identity, reads the persisted accounts, Account Attributes, and Fee Requests, and returns final account statuses and Fee Decisions. SQL performs configuration lookup, Region and Plan resolution, validation, condition evaluation, status derivation, and monetary calculation. Java coordinates the batch invocation and maps the results but contains no pricing behavior.

Invalid input does not have to abort the entire statement. The SQL can retain Attribute values as raw JSON, derive separate `is_present` and `is_valid` flags, validate JSON types before conversion, and cast only guarded values. A null typed value alone is insufficient because it would conflate missing, invalid, and explicit null input. Recognized invalid data can therefore become `MISSING_ATTRIBUTE`, `INVALID_ATTRIBUTE_TYPE`, or another agreed status, while an unhandled database failure aborts the chunk.

- **Benefits common to both database topologies:**
  - Executes relational lookup and pricing decisions set-wise and can return final results in one statement.
  - Provides one statement-level configuration view without a multi-query application snapshot.
  - Avoids transferring resolved Pricing Configuration to Java.
  - Can minimize application heap and CPU use and reduce application implementation size.
  - Centralizes pricing behavior in one database implementation used by every caller of the function.
  - Makes lack of result-order guarantees natural because results are correlated by account number and Fee Request ID.
  - May provide the best throughput when account data already resides in the evaluation database and representative query plans remain bounded by chunk size.
- **Costs common to both database topologies:**
  - Makes PostgreSQL or the native SQL implementation the actual Pricing Engine; a Java class around it is primarily a serialization and error-mapping adapter. That shape is not inherently slower, but the Java module no longer owns substantive business logic.
  - Requires a large SQL pipeline for status derivation, safe typed conversions, empty and duplicate Attributes, unconditional Reasons, multiple satisfied Reasons, and isolated Fee errors.
  - Couples pricing behavior to PostgreSQL features and the current relational schema.
  - Uses database CPU, memory, I/O, connections, and temporary working space for business computation. Low configuration-write traffic reduces contention but does not remove capacity considerations.
  - Makes repository mocks unsuitable for pricing-rule tests because mocking the SQL function also mocks the pricing behavior. Meaningful TDD must execute PostgreSQL, although the project already has PostgreSQL Testcontainers support.
  - Makes debugging and profiling depend more heavily on SQL plans, database fixtures, and database observability.
  - A stored function centralizes deployment of executable business behavior in the shared database. Rolling callers must remain compatible with its signature and semantics. Packaging native SQL with the engine server reduces function-version coupling but still couples the query to the schema.
  - Set-wise joins can still create large intermediate cardinalities inside PostgreSQL even when only aggregated results cross the network.

#### Keep account data and Pricing Configuration in the same database

The SQL implementation reads persisted account-chunk rows and Pricing Configuration locally.

- **Additional benefits:**
  - Avoids moving Pricing Configuration or persisted account data between databases.
  - Lets the worker invoke pricing by batch or chunk identity rather than fetching account rows and sending them back to the database.
  - Allows local joins, indexes, and a single database snapshot across account and configuration data.
  - Avoids cross-database consistency and configuration-transfer protocols.
- **Additional costs:**
  - Couples account-batch storage, Pricing Configuration, and pricing execution to one database's availability and capacity.

#### Fetch Pricing Configuration and pass it to the database holding account data

The batch worker or an adapter reads the smaller Pricing Configuration snapshot from its authoritative database and supplies it to the database that holds the account chunk. It may use JSON parameters, temporary or staging tables, database-native composite arrays, or another explicitly versioned transfer representation. SQL then evaluates accounts next to their stored data.

- **Additional benefits:**
  - Moves the smaller Pricing Configuration dataset rather than moving a much larger account batch.
  - Keeps Pricing Configuration authoritative in the pricing database while allowing computation to run beside account data.
  - Avoids returning a multiplied hybrid result to Java because SQL returns only final Pricing Decisions.
  - Allows account storage and decision storage to scale independently from the configuration database.
  - Can reuse one transferred configuration snapshot across several chunks if an explicit lifecycle and invalidation policy permits it.
- **Additional costs:**
  - Requires connections, credentials, failure handling, and observability for two databases.
  - Cannot obtain one atomic snapshot across independent databases without an additional configuration version or snapshot protocol.
  - Requires serialization and type mapping for Products, Branches, Regions, Plans, Fees, Reasons, conditions, and Attribute definitions.
  - Requires staging cleanup or transaction-scoped temporary data, plus indexing if the transferred configuration is queried at scale.
  - Re-transferring configuration for every chunk adds overhead; reusing it creates cache lifetime and invalidation decisions.
  - Creates an intermediate configuration contract that must remain compatible with both the authoritative schema and the SQL evaluator.
  - Moves pricing compute load to the account database and couples evaluation SQL to that database's engine and schema.
  - A partial failure can occur after configuration is fetched but before it is staged or evaluated, requiring the chunk to be retried safely.

## Decision

Resolve candidate Pricing Plans by submitted Pricing Date in the PostgreSQL configuration adapter,
then evaluate Region selection, exact Pricing Plan selection, validation, eligibility, Fee calculation,
and statuses in Java.

The adapter loads one immutable Pricing Configuration per Pricing Engine invocation using phased bulk
reads in one read-only `REPEATABLE_READ` transaction. Java evaluation starts after that transaction
closes. This decision selects the evaluation boundary; account-batch persistence, notification,
Pricing Decision persistence, and database topology remain separate open decisions.

## Rationale

Filtering candidate Pricing Plans in PostgreSQL reduces transfer of the configuration type expected to
have the greatest cardinality. Keeping the remaining behavior in Java preserves one explicit,
transport-independent Pricing Engine, supports fast behavioral tests with a deterministic
configuration repository, and makes the system more scalable for large size batches than the full SQL option.

This choice does not assume where future persisted account batches or Pricing Decisions will live.
Representative measurements may justify revisiting the boundary, but the current implementation no
longer leaves it open.

## Consequences

- The account-batch-ready notification identifies persisted work and does not carry account records.
- The mechanism used to deliver that notification does not depend on this decision.
- The pricing backend remains the only writer of Pricing Configuration.
- Pricing Decision storage remains a separate open choice.
- One Pricing Engine invocation observes one immutable Pricing Configuration loaded through phased
  bulk reads in a read-only `REPEATABLE_READ` transaction.
- Configuration consistency across all chunks of a logical batch remains outside this ADR.
- Engine behavior is tested through an in-memory Pricing Configuration repository; SQL filtering,
  mapping, bulk loading, and snapshot consistency require PostgreSQL integration tests.
- Pricing Plan active-period semantics must remain aligned between the adapter query and Java's exact
  Pricing Plan selection.
