---
status: current
verified: 2026-08-29
tags:
  - architecture
  - backend
---

# Backend architecture

The backend is a Java 21 Spring Boot application organized by feature package, with a separate `com.pricing.engine` package for evaluation behavior.

## Contract-first HTTP boundary

[openapi.yaml](../../../../pricing-backend/openapi.yaml) defines endpoints, request and response models, enums, and Jakarta validation annotations. Maven's OpenAPI Generator creates Java interfaces and models during the build. Controllers implement those generated interfaces; generated sources are build artifacts rather than hand-edited application code.

Endpoint families are:

- `/branches`, `/regions`, `/products`, `/fees`;
- `/account-attributes`, `/eligibility-reasons`, `/pricing-plans`;
- `/simulator/date`, `/simulator/options`;
- `/batch`.

See [[02 Architecture/API Contract]] before changing any endpoint or payload.

## Configuration feature shape

Most configuration packages use the same roles:

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

Flyway migrations under [db/migration](../../../../pricing-backend/src/main/resources/db/migration/) are shared by H2-compatible tests and PostgreSQL. PostgreSQL-only constraints live under [db/postgresql](../../../../pricing-backend/src/main/resources/db/postgresql/). Runtime Hibernate uses `ddl-auto=validate`.

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

The engine owns transport- and JPA-independent records:

- [AccountBatch.java](../../../../pricing-backend/src/main/java/com/pricing/engine/AccountBatch.java) for input;
- [PriceConfig.java](../../../../pricing-backend/src/main/java/com/pricing/engine/PriceConfig.java) for immutable configuration;
- [AccountBatchResult.java](../../../../pricing-backend/src/main/java/com/pricing/engine/AccountBatchResult.java) for statuses and Pricing Decisions;
- [RuleEngine.java](../../../../pricing-backend/src/main/java/com/pricing/engine/RuleEngine.java) as the interface;
- [PrototypeRuleEngine.java](../../../../pricing-backend/src/main/java/com/pricing/engine/PrototypeRuleEngine.java) as the implementation.

`JpaPriceConfigRepository` is the JPA adapter behind the engine-owned `PriceConfigRepository` interface. It filters candidate Pricing Plans in SQL by submitted Pricing Dates, then Java performs exact Region and Pricing Plan selection, validation, typed comparison, waiver evaluation, and amount calculation.

## Error boundary

[GlobalExceptionHandler.java](../../../../pricing-backend/src/main/java/com/pricing/backend/config/GlobalExceptionHandler.java) produces the contract's `ErrorResponse` and maps:

| Condition | HTTP result |
|---|---|
| Contract/Jakarta validation, malformed input, domain argument rule | `400` |
| Missing record | `404` |
| Duplicate code, record in use, relationship conflict | `409` |
| Pricing Configuration load failure | `503` |
| Unexpected exception | `500` |

Database constraint names are part of error mapping. A migration that renames a recognized constraint can silently change the user-facing response unless the handler and tests change with it.

## Time behavior

[SimulatorService.java](../../../../pricing-backend/src/main/java/com/pricing/backend/simulator/SimulatorService.java) wraps a process-local `Clock`. `PUT /simulator/date` replaces it with a fixed clock. The value is shared by Pricing Plan lifecycle checks and options, is not persisted, and resets to the system clock when the backend restarts.

## Test layers

- `PrototypeRuleEngineTests` exercise evaluation behavior with in-memory configuration.
- Spring Boot and MockMvc API tests exercise contracts, services, JPA mappings, errors, and end-to-end configuration behavior against H2 in PostgreSQL compatibility mode.
- Testcontainers PostgreSQL tests cover exclusion constraints, PostgreSQL migrations, configuration filtering, query shape, and `REPEATABLE_READ` snapshot behavior.
- `OpenApiContractAlignmentTests` checks the served contract boundary.

See [[05 Reference/Validation and Integrity]] for validation ownership and [[04 Change Guides/Implement a Feature or Change]] for change impact.

