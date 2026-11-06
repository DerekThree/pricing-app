---
status: current
verified: 2026-08-29
tags:
  - architecture
  - api
---

# API contract

Each provider owns its HTTP contract: [pricing-backend/openapi.yaml](../../../../pricing-backend/openapi.yaml)
defines the Backend API; [pricing-mock-server/openapi.yaml](../../../../pricing-mock-server/openapi.yaml)
defines the Mock Account Processor API.
The [engine contract](../../../../pricing-engine/openapi.yaml) defines its wake-up API.

```mermaid
flowchart TB
    Contract[openapi.yaml] -->|Maven OpenAPI Generator| Java[Java API interfaces and models]
    Contract -->|Orval| TypeScript[TypeScript client and models]
    Java --> Controllers[Backend controllers]
    TypeScript --> Dashboard[Dashboard routes]
    ProcessorContract[Mock Account Processor openapi.yaml] -->|Orval| ProcessorTypes[Processor client and models]
    ProcessorTypes --> Dashboard
```

## Backend generation

The Maven build generates Spring interfaces in `com.pricing.backend.generated.api` and models in `com.pricing.backend.generated.model`. Handwritten controllers implement the interfaces. Contract constraints become Jakarta validation on generated request models.

The engine uses the same Maven generation pattern with `com.pricing.engine.generated.api` and
`com.pricing.engine.generated.model`. `PricingController` implements `PricingApi` and delegates
to `PricingService`. The payload-free `POST /api/v1/work-available` returns an empty HTTP 202
acknowledgement; it does not confirm completed pricing or persisted recommendations.

## Dashboard generation

Orval generates separate clients and model namespaces under `app/generated/backend/` for the Backend
and `app/generated/accountProcessor/` for the Mock Account Processor. API generation cleans both
outputs first. The mutators preserve status, body, and headers rather than throwing for non-2xx
responses. `backendMutator` and `accountProcessorMutator` share `app/utils/apiMutator.ts`.
Configuration, Simulator options, and Application Date use the Backend client; Simulator
batches use the processor client at `POST /api/v1/mock/acc/batch`, retaining account-level
`pricingDate`. HTTP 202 returns `batchId` and `message`, rather than completed pricing results.

## Contract change surface

An endpoint or schema change normally affects all of these:

1. `pricing-backend/openapi.yaml`;
2. generated Java interfaces/models and handwritten controller/service/mapper use sites;
3. backend contract and API tests;
4. regenerated dashboard client/models;
5. dashboard route loaders/actions and form/result rendering;
6. Playwright request fixtures and response expectations;
7. `docs/Validations.md` when validation ownership or error behavior changes.

Generated code is evidence of the contract, not the editing surface. Change the contract and regenerate it.

## Response conventions

- Create returns `201`; successful reads and updates return `200`; deletion returns `204`.
- The Pricing Engine accepts generic wake-ups with `202` and no response body.
- Contract and business-rule validation normally return `400`.
- Missing resources return `404`.
- uniqueness, reference, and record-in-use conflicts return `409`.
- error bodies use `ErrorResponse.message`.

The shared dashboard CRUD action checks the expected success status for each operation. A backend status change therefore requires an intentional dashboard change even when the JSON body is unchanged.

## Account acceptance and recommendation correlation

Account acceptance and stored recommendations preserve three correlation levels:

- `batchId` identifies the account batch and its corresponding recommendation batch;
- `accountNumber` identifies an account within that batch and must be unique there;
- `feeRequestId` identifies a Fee Request within one account and must be unique there.

The same Fee Request ID may appear in different accounts, and one account may repeat the same Fee code under different Fee Request IDs. Consumers correlate by identifiers, not array order.

## Scalar Account Attribute values

The contract permits Account Attribute values that are strings, numbers, or booleans. Backend configuration conditions and Mock Account Processor submissions map their generated scalar interfaces through custom Jackson deserializers. The engine reads persisted Account Attribute scalars through a JPA converter. The Pricing Engine later compares the runtime value to the configured Account Attribute type and returns an account status for a mismatch.

Related implementation:

- [JacksonConfig.java](../../../../pricing-backend/src/main/java/com/pricing/backend/config/JacksonConfig.java)
- [AccountMapper.java](../../../../pricing-engine/src/main/java/com/pricing/engine/accountStore/AccountMapper.java)
- [PricingPersistencePostgresTests.java](../../../../pricing-engine/src/test/java/com/pricing/engine/PricingPersistencePostgresTests.java)

