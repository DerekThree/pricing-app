---
status: current
verified: 2026-08-29
tags:
  - architecture
  - backend
---

# Backend architecture

The backend is a Java 21 Spring Boot application organized by feature package, with evaluation owned by the standalone `pricing-engine/` server.

## Contract-first HTTP boundary

[openapi.yaml](../../../../pricing-backend/openapi.yaml) defines endpoints, request and response models, enums, and Jakarta validation annotations. Maven's OpenAPI Generator creates Java interfaces and models during the build. Controllers implement those generated interfaces; generated sources are build artifacts rather than hand-edited application code.

Endpoint families are:

- `/branches`, `/regions`, `/products`, `/fees`;
- `/account-attributes`, `/eligibility-reasons`, `/pricing-plans`;
- `/simulator/date`, `/simulator/options`;

See [[02 Architecture/API Contract]] before changing any endpoint or payload.

## Pricing data feature shape

Most pricing data packages use the same roles:

| Role | Responsibility |
|---|---|
| Controller | Implements a generated API interface and maps HTTP success/not-found semantics |
| Service | Owns transaction boundaries, orchestration, reference checks, and mutation rules |
| Validator | Holds service-layer rules that cannot be expressed correctly by contract or database constraints |
| Mapper | Converts JPA entities to generated response models |
| Repository | Spring Data access and relationship queries |
| Entity | JPA mapping and persistence relationships |

Use an existing neighboring package as the implementation pattern. Pricing Plans and Eligibility Reasons are more complex because they rebuild child collections and validate cross-record compatibility.

## Persistence model

The Engine owns Pricing Store initialization and Flyway execution. Migrations under
[db/migration](../../../../pricing-engine/src/main/resources/db/migration/) are shared by
H2-compatible tests and PostgreSQL. PostgreSQL-only constraints and runtime grants live under
[db/postgresql](../../../../pricing-engine/src/main/resources/db/postgresql/).
Backend production Flyway is disabled; its tests load the Engine's versioned migrations.
Runtime Hibernate uses `ddl-auto=validate`.

The Engine connects to an existing PostgreSQL database through `INITIALIZATION_URL`, using
`INITIALIZATION_USERNAME` and `INITIALIZATION_PASSWORD`, to create the Pricing Store and Account
Store databases and runtime logins outside a transaction. The same privileged login runs
Pricing Store, Account Store, and Recommendation Store migrations. Runtime datasource credentials
remain separate.
`PRICING_STORE_BACKEND_USERNAME` and `PRICING_STORE_BACKEND_PASSWORD` configure the
Backend login to provision; Backend uses matching `SPRING_DATASOURCE_USERNAME` and
`SPRING_DATASOURCE_PASSWORD`. Backend defaults to `pricingdb_backend` with pricing data CRUD
and sequence access; Engine defaults to `pricingdb_engine` with SELECT on the 15 business tables.
Neither runtime login owns the schema or can run migrations.

Account Store migrations live in the Engine's `db/account/`, with runtime grants in
`db/account-postgresql/`. Mock Server production Flyway is disabled; its PostgreSQL tests load
these Engine resources using a privileged connection before starting the restricted application.
H2 tests retain their separate SQL schema initialization.
`ACCOUNT_STORE_MOCK_SERVER_USERNAME` and `ACCOUNT_STORE_MOCK_SERVER_PASSWORD` configure the login
to provision for Mock Server, which uses matching `SPRING_DATASOURCE_USERNAME` and
`SPRING_DATASOURCE_PASSWORD`. The default login is `accountdb_mock_server`, with INSERT and SELECT
on the four Account Store tables and sequence access. The Engine uses `ACCOUNT_STORE_USERNAME`
and `ACCOUNT_STORE_PASSWORD`, defaulting to `accountdb_engine`, with SELECT on those tables and
table-wide UPDATE on `batch_outbox`. Neither runtime login owns the schema or can run migrations.

Important database-enforced relationships include:

- globally unique record codes;
- unique Region membership for each Branch, ZIP code, or state;
- foreign keys from Pricing Plans to Product and Region;
- a composite primary key for one Fee per Pricing Plan;
- a composite key for one Eligibility Reason per Pricing Plan Fee;
- non-negative Fee Amounts;
- inclusive active-period ordering and PostgreSQL exclusion of overlapping periods for one Product and Region;
- restrictive deletion of referenced records.

The current schema is defined by migrations. The root `DB Schema.txt` is historical design material, not the schema source of truth.

## Pricing Engine boundary

The standalone `pricing-engine/` server owns evaluation and pricing data snapshot reads. Backend
pricing data CRUD remains here; Pricing Store migrations belong to the Engine.
The synchronous batch endpoint, its contract operation, and engine-dependent wiring have been
removed. The engine independently reads accounts and persists transaction recommendations using
JPA repositories and separate local store transactions.

The engine owns transport- and JPA-independent records:

- [RuleEngineBatch.java](../../../../pricing-engine/src/main/java/com/pricing/engine/RuleEngineBatch.java) for input;
- [Pricing.java](../../../../pricing-engine/src/main/java/com/pricing/engine/ruleEngine/Pricing.java) for immutable pricing data;
- [RuleEngineBatchResult.java](../../../../pricing-engine/src/main/java/com/pricing/engine/RuleEngineBatchResult.java) for statuses and Pricing Decisions;
- [PrototypeRuleEngine.java](../../../../pricing-engine/src/main/java/com/pricing/engine/PrototypeRuleEngine.java) as the implementation.

`PricingRepository` loads the engine's immutable pricing data. It filters candidate
Pricing Plans in SQL by submitted Pricing Dates, then Java performs exact Region and Pricing Plan
selection, validation, typed comparison, waiver evaluation, and amount calculation.

## Error boundary

[GlobalExceptionHandler.java](../../../../pricing-backend/src/main/java/com/pricing/backend/config/GlobalExceptionHandler.java) produces the contract's `ErrorResponse` and maps:

| Condition | HTTP result |
|---|---|
| Contract/Jakarta validation, malformed input, domain argument rule | `400` |
| Missing record | `404` |
| Duplicate code, record in use, relationship conflict | `409` |
| Pricing data load failure | `503` |
| Unexpected exception | `500` |

Database constraint names are part of error mapping. A migration that renames a recognized constraint can silently change the user-facing response unless the handler and tests change with it.

## Time behavior

[SimulatorService.java](../../../../pricing-backend/src/main/java/com/pricing/backend/simulator/SimulatorService.java) wraps a process-local `Clock`. `PUT /simulator/date` replaces it with a fixed clock. The value is shared by Pricing Plan lifecycle checks and options, is not persisted, and resets to the system clock when the backend restarts.

## Test layers

- In `pricing-engine/`, moved `PrototypeRuleEngineTests` cover in-memory evaluation and moved
  `PricingRepositoryH2Tests` cover pricing data snapshots against H2 and server startup.
- Spring Boot and MockMvc API tests exercise contracts, services, JPA mappings, errors, and end-to-end pricing data behavior against H2 in PostgreSQL compatibility mode.
- Testcontainers PostgreSQL tests cover exclusion constraints, PostgreSQL migrations, pricing data filtering, query shape, and `REPEATABLE_READ` snapshot behavior.
- `OpenApiContractAlignmentTests` checks the served contract boundary.

See [[05 Reference/Validation and Integrity]] for validation ownership and [[04 Change Guides/Implement a Feature or Change]] for change impact.

