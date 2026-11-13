# For agents
- Use DB constraints whenever you can
- Disable inputs to prevent the user from entering invalid values whenever you can
- For validations that are not present in the front end, create a descriptive error message
- return appropriate error code
- Do not use business logic layer to validate things that are already validated by Jakarta or DB
- If using service layer for validations, put the code in the service's validator
- Look at how similar validations have been implemented and follow established conventions
- Update validation matrix when updating validations

# Validation Matrix

## Dashboard / Backend — Pricing Store

| Validation | UI | API contract | Backend logic | Status and Error message | DB |
|---|---|---|---|---|---|
| Record codes are 1–25 uppercase letters/digits | Yes | Yes | No | 400 — `branchCode must match "^[A-Z0-9]{1,25}$"` | Partial — only length/not-null/unique are enforced |
| Record names are non-empty and at most 100 characters | Yes | Yes | No | 400 — `branchName size must be between 1 and 100` | Partial — not-null and maximum length; blank strings are valid |
| Branch state is two uppercase letters | Yes | Yes | No | 400 — `state must match "^[A-Z]{2}$"` | Partial — only length is enforced |
| Branch ZIP code is five digits | Yes | Yes | No | 400 — `zipCode must match "^[0-9]{5}$"` | Partial — only length is enforced |
| Product type, fee type, attribute type, and reason operator are valid enum values | Yes | Yes | No | 400 — `Request body is malformed` | Yes |
| Record codes are unique | No | No | No | 409 — `A record with the same code already exists` | Yes |
| A region branch exists | Yes | No | No | 409 — `The request violates a record relationship` | Yes |
| A branch, state, or ZIP belongs to at most one region | Yes | No | No | 409 — `A record with the same code already exists` | Yes |
| A pricing plan product exists | Yes | No | No | 409 — `The request violates a record relationship` | Yes |
| A pricing plan region exists | Yes | No | No | 409 — `The request violates a record relationship` | Yes |
| Active Through is on or after Active From | Yes | No | No | 400 — `Active Through must be on or after Active From` | Yes |
| Pricing-plan active periods do not overlap for the same Product and Region | Yes | No | No | 400 — `Pricing plan active period overlaps an existing pricing plan` | Yes |
| A new pricing plan does not start before the application date | Yes | No | Yes | 400 — `activeFrom must be on or after the application current date` | No |
| An active plan can change only its name and Active Through | Yes | No | Yes | 400 — `Only planName and activeThrough can be updated for an active pricing plan` | No |
| A past plan can change only its name | Yes | No | Yes | 400 — `Only planName can be updated for a past pricing plan` | No |
| An active plan cannot end before the application date | Yes | No | Yes | 400 — `activeThrough must be on or after the application current date` | No |
| An active pricing plan cannot be deleted | No | No | Yes | 400 — `Active pricing plans cannot be deleted` | No |
| A pricing-plan fee exists | Yes | No | No | 409 — `The request violates a record relationship` | Yes |
| A fee is valid for the selected product type | Yes | No | Yes | 400 — `Fee with id <id> cannot be used for this product type` | No |
| A pricing plan does not contain the same fee twice | Yes | No | No | 400 — `A pricing plan cannot contain the same fee twice` | Yes |
| A pricing-plan fee amount is non-negative | Yes | Yes | No | 400 — `fees[<index>].amount must be greater than or equal to 0` | Yes |
| A pricing-plan eligibility reason exists | Yes | No | No | 409 — `The request violates a record relationship` | Yes |
| A pricing-plan eligibility reason is valid for the selected product type | No | No | Yes | 400 — `Eligibility reason with code <code> cannot be used for this product type` | No |
| A fee does not contain the same eligibility reason twice | Yes | No | No | 400 — `A fee cannot contain the same eligibility reason twice` | Yes |
| A Fee applies to at least one Product Type | Yes | Yes | No | 400 — `Applicable Product Types must contain at least one item` | No |
| A fee does not contain the same product type twice | Yes | No | No | 400 — `A fee cannot contain the same product type twice` | Yes |
| An Account Attribute applies to at least one Product Type | Yes | Yes | No | 400 — `Applicable Product Types must contain at least one item` | No |
| An Account Attribute does not contain the same Product Type twice | Yes | No | No | 400 — `An account attribute cannot contain the same product type twice` | Yes |
| Selected Eligibility Reason Attributes share at least one Product Type | No | No | Yes | 400 — `Applicable Product Types must contain at least one item` | No |
| A Fee definition cannot be updated when used by a Pricing Plan | No | No | Yes | 409 — `This fee is used by pricing plan with code <code>. Please update the pricing plan first.` | No |
| Only an Eligibility Reason's name can be updated when used by a Pricing Plan | No | No | Yes | 409 — `This eligibility reason is used by pricing plan with code <code>. Please update the pricing plan first.` | No |
| Only an Account Attribute's name can be updated when used by an Eligibility Reason | No | No | Yes | 409 — `This account attribute is used by eligibility reason with code <code>. Please update the eligibility reason first.` | No |
| A reason condition references an existing account attribute | Yes | No | No | 409 — `The request violates a record relationship` | Yes |
| A text condition uses only `=` or `<>`; a boolean condition uses `=` | Yes | No | No | No | No |
| A condition value matches its attribute type | Yes | No | Yes | 400 — `Condition value for account attribute <code> must be an integer` | No |
| A condition value is a string, number, or boolean | Yes | Yes | Yes | 400 — `Condition value must be a string, number, or boolean` | No |
| A Branch, Product, Region, Fee, Account Attribute, or Eligibility Reason cannot be deleted while referenced | No | No | Yes | 409 — `This <record> is used by <referencing record> with code <code>. Please update the <referencing record> first.` | Yes |

## Mock Account Processor — Account Store

| Validation | API contract | Processor logic | Status and Error message | DB |
| --- | --- | --- | --- | --- |
| Submission body matches the request schema | Yes | No | 400 — `INVALID_BATCH`, `Request body is malformed` | No |
| Submission collections contain no null items | Yes | Yes | 400 — `INVALID_BATCH`, `<Collection> must not contain null items: <path>` | No |
| Required submission fields are present | Yes | No | 400 — `INVALID_BATCH`, `<fieldPath> must not be null` | Yes |
| Submitted codes contain 1–25 uppercase letters or digits | Yes | No | 400 — `INVALID_BATCH`, `<fieldPath> must match "^[A-Z0-9]{1,25}$"` | Partial |
| Accounts per Pricing Batch must not exceed `BATCH_MAX_ACCOUNTS` (default `100000`) | Yes | Yes | 400 — `INVALID_BATCH`, `Pricing Batch exceeds the limit of <limit> accounts (<count> submitted).` | No |
| Previously accepted Batch IDs are rejected regardless of payload differences | Yes | Yes | 409 — `BATCH_ALREADY_ACCEPTED`, `This Pricing Batch has already been accepted [batch_outbox]: Key (batch_id)=(<batchId>) already exists.` | Yes |
| Submitted Fee Request IDs are unique within an Account | No | Yes | 400 — `INVALID_BATCH`, `Fee Request IDs must be unique within an account: <fieldPath> (accountNumber=<accountNumber>, feeRequestId=<feeRequestId>, code=<code>); duplicates <otherFieldPath>` | Yes |
| Attribute values must be string, number, or boolean scalars | Yes | No | 400 — `INVALID_BATCH`, `Account Attribute value must be a string, number, or boolean` | Yes |
| A supplied transaction amount is nonnegative | Yes | No | 400 — `INVALID_BATCH`, `<fieldPath> must be greater than or equal to 0` | Yes |
| A supplied transaction amount uses increments of 0.01 | Yes | Yes | 400 — `INVALID_BATCH`, `Transaction Amount must use increments of 0.01: accounts[<accountIndex>].fees[<feeIndex>].transactionAmount (accountNumber=<accountNumber>, feeRequestId=<feeRequestId>, code=<code>)` | Yes |
| An explicit null transaction amount is rejected; omission is allowed | Yes | No | 400 — `INVALID_BATCH`, `Request body is malformed at <fieldPath>` | No |
| Accounts reference a batch; attributes and Fee Requests reference an account | No | No | 400 — `INVALID_BATCH`, `The request violates a database constraint` | Yes |

## Pricing Engine — Recommendation Store

Outcome codes are stored in Recommendation Store columns: `account_recommendations.status` for accounts and `fee_request_recommendations.status` for Fee Requests. They are not outbox errors.

| Validation | Engine logic | DB | Outcome |
| --- | --- | --- | --- |
| A required Batch Account Attribute occurs at most once | Yes | No | `DUPLICATE_ATTRIBUTE` |
| A supplied required Batch Account Attribute matches its configured type | Yes | No | `INVALID_ATTRIBUTE_TYPE` |
| Every required Batch Account Attribute is supplied | Yes | No | `MISSING_ATTRIBUTE` |
| A persisted Eligibility Reason condition uses an operator supported by its configured Attribute type during Pricing Batch evaluation | Yes | Partial — operator values constrained, not compatibility with attribute type | `INVALID_ELIGIBILITY_CONDITION` |
| A Batch Account has an applicable Pricing Plan for its Product, Region, and Pricing Date | Yes | No | `PLAN_NOT_FOUND` |
| One Recommendation Outbox row per batch identifier | No | Yes | Duplicate batch IDs are rejected; existing recommendations are retained |
