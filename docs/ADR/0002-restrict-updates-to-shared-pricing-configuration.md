# Restrict updates to shared configuration used by Pricing Plans

## Status

Implemented

## Context

The Pricing Plan lifecycle makes a Pricing Plan's own Fees, Fee Amounts, and attached Eligibility Reasons immutable after the Plan becomes active. Fees and Eligibility Reasons are shared records, however, and Eligibility Reasons use shared Account Attributes. Updating one of those records can still change the behavior of an active or past Pricing Plan without updating the Pricing Plan itself.

## Options Considered

- **Allow shared Fees, Eligibility Reasons, and Account Attributes to remain mutable.**
  - **Benefits:** Administrators can correct shared configuration immediately without creating replacement records.
  - **Costs:** An update can indirectly change active or historical pricing behavior, undermining the lifecycle lock and auditability.
- **Snapshot or version shared configuration when a Pricing Plan becomes active.**
  - **Benefits:** Active and past Pricing Plans retain their exact configuration while shared records can evolve for future use.
  - **Costs:** Requires a versioning or snapshot model, a clear point at which a scheduled Pricing Plan is pinned, and additional administration for understanding relationships between versions.
- **Restrict updates to shared configuration referenced by any Pricing Plan.**
  - **Benefits:** Keeps the first iteration simple, preserves the lifecycle lock, and retains shared records without a snapshot model.
  - **Costs:** Corrections require replacement configuration and a scheduled Pricing Plan must be updated to use it. The system must follow direct and transitive references when enforcing the restriction.

## Decision

Use reference-aware update restrictions rather than snapshots or versions in the first iteration.

- A **Fee** definition cannot be updated once a Pricing Plan contains it.
- An **Eligibility Reason** definition cannot be updated once Pricing Plan contains it.
- An **Account Attribute** definition cannot be updated once an Eligibility Reason uses it.
- Names of shared records remain mutable.

## Rationale

The date-based lifecycle would be incomplete if its shared Fees or Eligibility Reasons could be changed in place. Restricting Fee and Eligibility Reason definition changes once used protects every configured Pricing Plan, including scheduled Plans. Account Attribute types also define the interpretation of Eligibility Reason condition values. Restricting their definition changes once used prevents an existing Reason from becoming invalid or changing meaning.

Snapshots and versions could provide greater reuse in the future, but they introduce a separate model for version ownership, activation timing, and administrator-facing dependency information. The reference-aware restriction is the smallest policy that prevents indirect changes to any Pricing Plan, including scheduled Plans that already reference shared configuration.

## Consequences

Administrators who need to change protected configuration must create a replacement Fee, Eligibility Reason, or Account Attribute and use it in a scheduled Pricing Plan. The backend must remain authoritative for checking whether any Pricing Plan references the configuration; the dashboard may communicate the restriction but cannot enforce it alone.

Tests must cover direct Fee and Eligibility Reason references, Account Attributes used by Eligibility Reasons, references from active, past, and scheduled Plans that reject definition updates, and name-only updates that remain allowed. A future snapshot or versioning ADR may supersede this policy if replacement records become an operational burden.
