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

| Validation | UI | API contract | Backend logic | Status and Error message | DB |
|---|---|---|---|---|---|
| Record codes are 1–25 uppercase letters/digits | Yes | Yes | No | 400 — `branchCode must match "^[A-Z0-9]{1,25}$"` | No — only length/not-null/unique are enforced |
| Record names are non-empty and at most 100 characters | Yes | Yes | No | 400 — `branchName size must be between 1 and 100` | Partial — not-null and maximum length; blank strings are valid |
| Branch state is two uppercase letters | Yes | Yes | No | 400 — `state must match "^[A-Z]{2}$"` | No — only length is enforced |
| Branch ZIP code is five digits | Yes | Yes | No | 400 — `zipCode must match "^[0-9]{5}$"` | No — only length is enforced |
| Product type, fee type, attribute type, and reason operator are valid enum values | Yes | Yes | No | 400 — `Request body is malformed` | Yes — check constraints |
| Record codes are unique | No | No | No | 409 — `A record with the same code already exists` | Yes — unique constraint |
| A region branch exists | Yes | No | No | 409 — `The request violates a record relationship` | Yes — FK |
| A branch, state, or ZIP belongs to at most one region | Yes | No | No | 409 — `A record with the same code already exists` | Yes — unique constraints |
| A pricing plan product exists | Yes | No | No | 409 — `The request violates a record relationship` | Yes — FK |
| A pricing plan region exists | Yes | No | No | 409 — `The request violates a record relationship` | Yes — FK |
| Active Through is on or after Active From | Yes | No | No | 400 — `Active Through must be on or after Active From` | Yes — check constraint |
| Pricing-plan active periods do not overlap for the same Product and Region | Yes | No | No | 400 — `Pricing plan active period overlaps an existing pricing plan` | Yes — PostgreSQL exclusion constraint |
| A new pricing plan does not start before the application date | Yes | No | Yes | 400 — `activeFrom must be on or after the application current date` | No |
| An active plan can change only its name and Active Through | Yes | No | Yes | 400 — `Only planName and activeThrough can be updated for an active pricing plan` | No |
| A past plan can change only its name | Yes | No | Yes | 400 — `Only planName can be updated for a past pricing plan` | No |
| An active plan cannot end before the application date | Yes | No | Yes | 400 — `activeThrough must be on or after the application current date` | No |
| An active pricing plan cannot be deleted | No | No | Yes | 400 — `Active pricing plans cannot be deleted` | No |
| A pricing-plan fee exists | Yes | No | No | 409 — `The request violates a record relationship` | Yes — FK |
| A fee is valid for the selected product type | Yes | No | Yes | 400 — `Fee with id <id> cannot be used for this product type` | No |
| A pricing plan does not contain the same fee twice | Yes | No | No | 400 — `A pricing plan cannot contain the same fee twice` | Yes — composite primary key |
| A pricing-plan fee amount is non-negative | Yes | Yes | No | 400 — `fees[<index>].amount must be greater than or equal to 0` | Yes — check constraint |
| A pricing-plan eligibility reason exists | Yes | No | No | 409 — `The request violates a record relationship` | Yes — FK |
| A pricing-plan eligibility reason is valid for the selected product type | No | No | Yes | 400 — `Eligibility reason with code <code> cannot be used for this product type` | No |
| A fee does not contain the same eligibility reason twice | Yes | No | No | 400 — `A fee cannot contain the same eligibility reason twice` | Yes — composite primary key |
| A Fee applies to at least one Product Type | Yes | Yes | No | 400 — `Applicable Product Types must contain at least one item` | No — child rows cannot require at least one row |
| A fee does not contain the same product type twice | Yes | No | No | 400 — `A fee cannot contain the same product type twice` | Yes — unique constraint |
| An Account Attribute applies to at least one Product Type | Yes | Yes | No | 400 — `Applicable Product Types must contain at least one item` | No — child rows cannot require at least one row |
| An Account Attribute does not contain the same Product Type twice | Yes | No | No | 400 — `An account attribute cannot contain the same product type twice` | Yes — unique constraint |
| Selected Eligibility Reason Attributes share at least one Product Type | No | No | Yes | 400 — `Applicable Product Types must contain at least one item` | No |
| A Fee definition cannot be updated when used by a Pricing Plan | No | No | Yes | 409 — `This fee is used by pricing plan with code <code>. Please update the pricing plan first.` | No |
| Only an Eligibility Reason's name can be updated when used by a Pricing Plan | No | No | Yes | 409 — `This eligibility reason is used by pricing plan with code <code>. Please update the pricing plan first.` | No |
| Only an Account Attribute's name can be updated when used by an Eligibility Reason | No | No | Yes | 409 — `This account attribute is used by eligibility reason with code <code>. Please update the eligibility reason first.` | No |
| A reason condition references an existing account attribute | Yes | No | No | 409 — `The request violates a record relationship` | Yes — FK |
| A text condition uses only `=` or `<>`; a boolean condition uses `=` | Yes | No | No | N/A — No error; an invalid type-specific operator is accepted | No |
| A condition value matches its attribute type | Yes | No | Yes | 400 — `Condition value for account attribute <code> must be an integer` | No |
| A condition value is a string, number, or boolean | Yes | Yes | Yes | 400 — `Condition value must be a string, number, or boolean` | No |
| A Branch, Product, Region, Fee, Account Attribute, or Eligibility Reason cannot be deleted while referenced | No | No | Yes | 409 — `This <record> is used by <referencing record> with code <code>. Please update the <referencing record> first.` | Yes — restrictive FK |
| Batch ID is a UUID | No | Yes | No | 400 — generated request validation | No |
| A Batch contains at least one Account | No | Yes | No | 400 — generated request validation | No |
| A Batch Account contains at least one Fee Request | No | Yes | No | 400 — generated request validation | No |
| Batch Account, Attribute, and Fee Request collections contain no null elements | No | Yes | Yes | 400 — `<collection> must not contain null items` | No |
| Account Number is an uppercase alphanumeric string no longer than 25 characters | No | Yes | No | 400 — generated request validation | No |
| Fee Request ID is a required 64-bit integer | No | Yes | No | 400 — generated request validation | No |
| Account Numbers are unique within a Pricing Batch | No | No | Yes | 400 — `Account numbers must be unique within the Pricing Batch` | No |
| Fee Request IDs are unique within one Account | No | No | Yes | 400 — `Fee Request IDs must be unique within an account` | No |
| A Batch Account Attribute value is a string, number, or boolean | No | Yes | No | 400 — generated request validation | No |
| A required Batch Account Attribute occurs at most once | No | No | Yes | HTTP 200 account outcome `DUPLICATE_ATTRIBUTE`; no error message | No |
| A supplied required Batch Account Attribute matches its configured type | No | No | Yes | HTTP 200 account outcome `INVALID_ATTRIBUTE_TYPE`; no error message | No |
| Every required Batch Account Attribute is supplied | No | No | Yes | HTTP 200 account outcome `MISSING_ATTRIBUTE`; no error message | No |
| A persisted Eligibility Reason condition uses an operator supported by its configured Attribute type during Pricing Batch evaluation | No | No | Yes | HTTP 200 Fee outcome `ERROR`; no error message | Partial â€” the operator is constrained, but the operator-and-type combination is not |
| A Batch Account has an applicable Pricing Plan for its Product, Region, and Pricing Date | No | No | Yes | HTTP 200 account outcome `PLAN_NOT_FOUND`; no error message | No |
| A present Batch transaction amount is non-null, non-negative, and uses increments of 0.01 | No | Yes | Yes | 400 — generated null/minimum validation or `Transaction Amount must use increments of 0.01` | No |
