# Use a date-based Pricing Plan lifecycle

## Status

Implemented

## Context

Should updates to active pricing plans be allowed?

## Options Considered

- **Allow updates to active Pricing Plans.**
  - **Benefits:** Simpler validation, immediate changes in an emergency, and straightforward correction of pricing mistakes.
  - **Costs:** Pricing queries can produce inconsistent results during a business day; changes may create regulatory exposure and make pricing mistakes easier.
- **Lock a Pricing Plan based on its effective dates.**
  - **Benefits:** Consistent pricing throughout the business day and protection against accidental pricing changes.
  - **Costs:** Pricing mistakes are harder to correct, and the system must also manage updates to Pricing Plan elements such as Fees, Eligibility Reasons, and Account Attributes.
- **Introduce an approval workflow that locks a Pricing Plan once it is approved.**
  - **Benefits:** Protection against pricing mistakes, including a Pricing Plan becoming active before its changes are final.
  - **Costs:** An additional workflow is unsuitable for this iteration, and restrictions on updates to Pricing Plan elements are still needed.

## Decision

Use a date-based, three-stage Pricing Plan lifecycle: scheduled, active, and past. The application current date determines a Pricing Plan's stage and controls its mutability.

- **Scheduled** Pricing Plans retain full mutability.
- **Active** Pricing Plans may update only Plan Name and Active Through. May not be deleted.
- **Past** Pricing Plans may update only Plan Name and be deleted.

## Rationale

A scheduled Pricing Plan has not yet affected pricing, so administrators can correct mistakes or revise decisions made at creation. For an active Pricing Plan, extending or shortening its future active period is a valid business need and does not revise prices already in effect. A past Pricing Plan's Active Through cannot change because there is no use case for it and because it would change the history of when the plan was active. Plan Name remains editable because it is functionally irrelevant and meant only for intuitive meaning to the user.

Allowing updates to active Pricing Plans was rejected as unrealistic for the banking domain.

An approval workflow was rejected for this iteration because its additional states and workflow are disproportionate to the feature. It remains a viable future option if the domain requires explicit approval before pricing takes effect.

## Consequences

Updates to fees, eligibility requirements, and account attributes need to be managed to prevent indirect changes to active and past pricing plans. There is a need to store the history of deletions and possibly updates for audit purposes, and to simulate date changes during an app demo.
