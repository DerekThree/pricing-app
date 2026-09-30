---
status: current
verified: 2026-08-29
tags:
  - change-guide
---

# Implement a feature or change

Use this note to find the implementation seam and the evidence that defines correct behavior. Repository instructions still govern the execution process.

## Start from the behavior

1. Name the affected concepts using [[01 Domain/CONTEXT]].
2. Check the ADRs linked from [[01 Domain/Concept Relationships]] when the change touches lifecycle, shared configuration, Product Applicability, engine evaluation placement, or planned notification architecture.
3. Decide whether the behavior is current or planned using [[05 Reference/Current and Planned System]].
4. Read the contract, implementation, migration, validation matrix, and tests that already own the behavior.

## Change impact map

| Change | Primary backend seam | Primary dashboard seam | Essential evidence |
|---|---|---|---|
| Add a configuration record type | OpenAPI schema/endpoints; new feature package; migration | list and CRUD routes; generated client | neighboring CRUD API and browser tests |
| Change a configuration field | OpenAPI model; entity/migration; mapper; service | generated model; list/form | contract alignment, API tests, validation matrix |
| Change Pricing Plan lifecycle | `PricingPlanValidator`, options, database periods | `pricingPlans/crud.tsx` disabled/date behavior | ADR 0001 and `PricingPlanApiTests` |
| Change Product Applicability | Fee/Account Attribute entities and validators; Eligibility Reason derivation | related forms and option filtering | ADR 0003 plus API and Playwright tests |
| Change Region resolution | `PrototypeRuleEngine`; Region persistence constraints | Region form/options | engine tests and Region API tests |
| Change Pricing Decision logic | engine-owned records and `PrototypeRuleEngine` | simulator response rendering | engine tests, batch API tests, simulator E2E |
| Change batch request/result | `openapi.yaml`; batch validator/mapper/controller | regenerated client; simulator composition/correlation | contract API tests and simulator E2E |
| Change a database constraint | Flyway migration; entity mapping; exception handler | error display only if behavior changes | H2 API tests and PostgreSQL Testcontainers tests |

## Configuration CRUD seam

For an ordinary configuration feature, trace one neighboring package end to end:

```text
openapi.yaml
  -> generated API interface and request/response models
  -> Controller
  -> Service / Validator
  -> Mapper / Repository / Entity
  -> Flyway migration
  -> API tests
  -> generated dashboard client
  -> list route and CRUD route
  -> Playwright behavior
```

Keep transaction ownership in the service. Use a validator for cross-record or lifecycle rules that cannot be owned by the contract or database. Preserve database constraints as the final relationship and concurrency boundary.

## Pricing Engine seam

Keep evaluation behavior inside `com.pricing.engine`. Engine records should not depend on generated HTTP models or JPA entities. Persistence-specific filtering and graph loading belong behind `PriceConfigRepository`; mapping from JPA entities belongs in the batch adapter.

When adding a status or Pricing Decision field, update the engine model and behavior first, then map it through `BatchMapper` and the OpenAPI model. Verify identifier correlation and ensure one failed Fee Request does not abort unrelated work unless the new behavior deliberately changes failure isolation.

## Dashboard seam

Use route loaders for initial reads and route actions or fetchers for writes. Standard CRUD pages should reuse `createClientLoader`, `createClientAction`, `ListPage`, and `CrudPageTopMenu`. Keep only feature-specific state and dependency handling in the route component.

For Product-dependent data, carry Product Applicability through options rather than hard-coding Product Types. For asynchronous dependent options, make stale-response protection explicit as the Pricing Plan page does with echoed Product and Region IDs.

## Contract seam

Follow [[02 Architecture/API Contract]]. Do not hand-edit generated Java or TypeScript. A contract change is complete only when both repositories compile against regenerated output and all application use sites match the new shapes.

## Validation seam

Consult [[05 Reference/Validation and Integrity]] before placing a new rule. If the validation matrix changes, update [Validations.md](../../../Validations.md) in the same change so UI, contract, backend, error, and database ownership remain visible together.

## Completion evidence

A change is accounted for when:

- every affected domain invariant has one authoritative enforcement path and appropriate defense in depth;
- the OpenAPI contract, generated consumers, handwritten code, migrations, and validation matrix agree;
- focused tests cover the new behavior at the lowest useful layer;
- cross-boundary behavior has an API or browser test;
- PostgreSQL-specific behavior has PostgreSQL evidence rather than H2-only evidence;
- this wiki is updated if the application mental model or implementation seam changed.

