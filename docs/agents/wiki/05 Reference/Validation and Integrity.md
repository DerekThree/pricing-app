---
status: current
verified: 2026-08-29
tags:
  - reference
  - validation
---

# Validation and integrity

The authoritative per-rule matrix is [docs/Validations.md](../../../Validations.md). It records UI prevention, OpenAPI validation, backend logic, HTTP/error behavior, and database enforcement. Use this note to understand the layers; update the matrix when a rule changes.

## Ownership layers

| Layer | Best fit | Examples in this application |
|---|---|---|
| Dashboard | Prevent impossible or incomplete user input and filter choices | required fields, patterns, Product-applicable options, non-overlapping date picker, one Incomplete Pricing Plan Fee at a time |
| OpenAPI/Jakarta | Request-shape and scalar constraints shared by every HTTP caller | required collections, lengths, patterns, enum values, non-negative amounts |
| Service validator | Cross-record, lifecycle, or typed semantic rules needing application context | Pricing Plan mutability, shared-definition locks, derived Product Applicability, condition-value type normalization |
| Database | Referential, uniqueness, range, and concurrency-safe invariants | foreign keys, unique codes/memberships, composite keys, active-period ordering and exclusion |
| Pricing Engine status | Per-account or per-Fee Request evaluation outcomes that should not reject the whole batch | missing plan, missing required Account Attribute, Fee not found, invalid persisted condition |

Avoid treating these layers as interchangeable. A dashboard check improves interaction but cannot protect other API callers. A service check cannot replace a concurrency-safe database constraint. A database rejection may need named exception mapping to produce a useful contract error.

## Error semantics

Configuration requests use HTTP errors because the submitted mutation failed. Pricing evaluation uses a mixed model:

- malformed or structurally invalid Pricing Batches return HTTP `400`;
- a configuration-load failure returns HTTP `503`;
- expected account-resolution and Fee evaluation failures return HTTP `200` with isolated account or Fee statuses.

This separation lets one invalid account or Fee Request avoid aborting other independent work in the Pricing Batch.

## Historical integrity

Historical integrity is enforced directly and transitively:

- Pricing Plan lifecycle restricts edits after activation;
- shared Fee and Eligibility Reason definitions are locked once a Pricing Plan references them;
- Account Attribute definitions are locked once an Eligibility Reason references them;
- names remain mutable because they do not change pricing behavior;
- membership order changes are allowed when membership itself is unchanged.

See [ADR 0001](../../../ADR/0001-use-a-date-based-pricing-plan-lifecycle.md) and [ADR 0002](../../../ADR/0002-restrict-updates-to-shared-pricing-configuration.md).

## Database-specific behavior

Most backend tests use H2 in PostgreSQL compatibility mode and the common Flyway migrations. PostgreSQL-specific migrations add the active-period exclusion constraint, and Testcontainers tests verify that constraint and snapshot behavior. A change involving PostgreSQL exclusion, isolation, query behavior, or SQL-state mapping needs PostgreSQL coverage.

## High-risk alignments

Check these pairs whenever either side changes:

- OpenAPI validation annotations and dashboard input constraints;
- JPA column/relationship mappings and Flyway migrations;
- database constraint names and `GlobalExceptionHandler` mappings;
- Pricing Plan active-period filtering in `JpaPriceConfigRepository` and inclusive selection in `PrototypeRuleEngine`;
- Account Attribute type options, condition normalization, JSON scalar deserialization, and runtime engine type checks;
- engine status/decision combinations, `BatchMapper`, OpenAPI schemas, and simulator rendering.

## Primary references

- [Validation matrix](../../../Validations.md)
- [GlobalExceptionHandler.java](../../../../pricing-backend/src/main/java/com/pricing/backend/config/GlobalExceptionHandler.java)
- [PricingPlanValidator.java](../../../../pricing-backend/src/main/java/com/pricing/backend/pricingplan/PricingPlanValidator.java)
- [EligibilityReasonValidator.java](../../../../pricing-backend/src/main/java/com/pricing/backend/eligibilityreason/EligibilityReasonValidator.java)
- [BatchValidator.java](../../../../pricing-backend/src/main/java/com/pricing/backend/batch/BatchValidator.java)
- [PostgreSQL active-period migration](../../../../pricing-backend/src/main/resources/db/postgresql/V17__prevent_overlapping_pricing_plan_active_periods.sql)

