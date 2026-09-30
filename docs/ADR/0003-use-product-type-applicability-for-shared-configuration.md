# Use Product-Type Applicability for Shared Configuration

## Status

Accepted. Implementation is complete.

## Context

Fees, Account Attributes, and Eligibility Reasons are reusable definitions. Fees and Account
Attributes have explicit Product Type applicability. An Eligibility Reason's applicability follows
from the Account Attributes used by its conditions and would be redundant persisted state.

## Options Considered

- **Keep Account Attributes and Eligibility Reasons global.**
  - **Benefits:** No new applicability data or compatibility rule.
  - **Costs:** Product-specific configuration exposes irrelevant Attributes and pushes inapplicable data into future processor requests.
- **Duplicate definitions for each Product Type.**
  - **Benefits:** Compatibility follows from record ownership.
  - **Costs:** Repeated definitions diverge and cannot be shared across Product Types.
- **Persist Product Types on Fees, Account Attributes, and Eligibility Reasons.**
  - **Benefits:** Every definition's applicability is explicit and directly queryable.
  - **Costs:** Eligibility Reason applicability duplicates its condition Attributes and requires a compatibility invariant to prevent conflicting state.
- **Derive Eligibility Reason Product Types from its condition Attributes.**
  - **Benefits:** The Reason cannot disagree with its Attributes, and administrators do not maintain redundant applicability.
  - **Costs:** Consumers must compute Reason applicability when they need it.

## Decision

Use required, persisted multi-select Product Types applicability lists for Fees and Account
Attributes. Derive an Eligibility Reason's Product Types as the intersection of the Product Types of
all Account Attributes used by its conditions.

- An Eligibility Reason with no conditions applies to all Product Types.
- Eligibility Reason Product Types are not stored in the database or accepted in write requests.
- The Eligibility Reason CRUD page recomputes Product Types immediately as conditions change and
  displays them in a disabled multi-select control.
- Eligibility Reason Attribute options include their Product Types so the dashboard can perform the
  derivation without another request.
- Pricing Plan choices use the derived Eligibility Reason Product Types for compatibility with the
  selected Product.
- Product Type membership, rather than presentation order, determines whether a persisted Fee or
  Account Attribute definition has changed for lifecycle validation.
- A Product Type introduced in the future requires explicit applicability assignments for Fees and
  Account Attributes. A conditionless Eligibility Reason includes it automatically.

## Rationale

Product applicability keeps reusable definitions shared without modelling irrelevant account data as
globally required. Deriving a Reason's applicability makes its meaning follow directly from the data
needed to evaluate it and eliminates redundant state that could contradict its Attributes.

## Consequences

The contract exposes Product Types on Eligibility Reason Attribute options, while the Eligibility
Reason entity and request remain unchanged. Consumers that need Reason applicability must calculate
the intersection rather than query a stored value. Tests must cover persisted Fee and Account
Attribute applicability, the conditionless Reason rule, intersections, live CRUD updates, Pricing Plan
Reason filtering, and lifecycle locks.
