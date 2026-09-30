---
aliases:
  - Domain Vocabulary
  - Ubiquitous Language
status: current
verified: 2026-08-29
tags:
  - domain
---

# Domain vocabulary

The canonical definitions live in the repository [CONTEXT.md](../../../../CONTEXT.md). This note keeps the same vocabulary close to the rest of the vault and emphasizes how the terms connect. If wording diverges, the repository `CONTEXT.md` wins.

## Configuration

### Pricing Plan

A pricing configuration for one Product and one Region over an inclusive effective period. Its lifecycle is scheduled, active, or past relative to the application current date. A Pricing Plan may contain no Pricing Plan Fees.

Use **Pricing Plan**, not “plan record” or “pricing row.”

### Pricing Plan Fee

A reusable Fee attached to a Pricing Plan with a Fee Amount and zero or more Eligibility Reasons. The same Fee may be used by many Pricing Plans, but only once within one Pricing Plan.

Use **Pricing Plan Fee**, not “fee row” or “fee entry.”

### Fee Amount

The non-negative configured value of a Pricing Plan Fee. It is a USD amount for a flat Fee and a percentage rate for a percentage Fee.

Use **Fee Amount**, not “price” or “fee value.”

### Incomplete Pricing Plan Fee

A Pricing Plan Fee whose Fee or valid Fee Amount is missing. The dashboard requires it to be completed before another Pricing Plan Fee can be added.

Use **Incomplete Pricing Plan Fee**, not “new fee” or “partial fee.”

### Secondary Pricing Plan Options

Product-and-Region-specific form data loaded after both selections exist. It contains eligible Fees, Eligibility Reasons, unavailable active periods, and the selected Product and Region IDs.

Use **Secondary Pricing Plan Options**, not “contextual options.”

### Eligibility Reason

A set of Account Attribute conditions. Every condition in one Eligibility Reason must be satisfied. A Pricing Plan Fee is eligible for waiver when any attached Eligibility Reason is satisfied. A reason without conditions is unconditionally satisfied.

Use **Eligibility Reason**, not “waiver reason,” “fee exception,” or “reason row.”

### Account Attribute

A named, typed property of an account that applies to one or more Product Types and is evaluated by an Eligibility Reason condition.

Use **Account Attribute**, not “account field” or “eligibility input.”

### Product Applicability

The Product Types for which reusable configuration can be used. Fees and Account Attributes store a non-empty list. An Eligibility Reason derives the intersection shared by its condition Account Attributes; a reason without conditions applies to all Product Types.

Use **Product Applicability**, not “product category” or “universal applicability.”

## Evaluation

### Pricing Batch

A caller-identified collection of account records submitted together for pricing evaluation. The current API identifies it with `batchId`.

Use **Pricing Batch**, not “batch job” or “simulator run.”

### Pricing Engine

The evaluator that resolves each account's Region and Pricing Plan and produces a Pricing Decision for each Fee Request.

Use **Pricing Engine**, not “rule engine” or “fee calculator” in domain explanations. `RuleEngine` remains an implementation interface name.

### Pricing Date

The date on which Pricing Plan applicability is evaluated for one account in a Pricing Batch. It is distinct from the application current date used to determine Pricing Plan lifecycle mutability.

Use **Pricing Date**, not “processing date” or “system date.”

### Fee Request

One independently identified request to evaluate a configured Fee for an account. Repeated requests for the same Fee code are allowed when their Fee Request IDs differ.

Use **Fee Request**, not “fee row” or “requested Fee.”

### Pricing Decision

The successful outcome of a Fee Request: either charged with a monetary amount or waived with every satisfied Eligibility Reason code.

Use **Pricing Decision**, not “fee result” or “eligibility result.” A Fee Request can instead have a failure status and no Pricing Decision.

## Supporting records

The code also uses these supporting concepts:

- A **Branch** has a code, name, state, and ZIP code.
- A **Region** owns selections of Branches, ZIP codes, and states used by Region resolution.
- A **Product** has a Product Type (`DEPOSIT`, `CD`, or `CREDIT`).
- A reusable **Fee** has a code, name, flat-or-percentage type, and Product Applicability. It has no amount until it becomes a Pricing Plan Fee.
- The **application current date** is an in-memory clock used by Pricing Plan lifecycle rules and the simulator. It is not the Pricing Date definition.

See [[01 Domain/Concept Relationships]] for the model as a graph.

