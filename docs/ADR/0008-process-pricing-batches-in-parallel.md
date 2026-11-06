---
status: accepted
---

# Process Pricing Batches in parallel

This accepted design does not describe implemented behavior.

## Dispatch and ownership

- Support concurrent workers across multiple Pricing Engine instances. Each instance has its own configurable worker cap; calculating workers and workers waiting through retries or recovery all count toward it.
- Discovery selects Account Outbox rows with `processed = false AND error IS NULL` and skips rows already claimed by another worker. SQL `NULL` means no error.
- Startup and wake-ups with available capacity discover work and start workers up to the cap. Wake-ups received at capacity are ignored.
- When a worker finishes, release its slot and trigger discovery regardless of the remaining worker count. Coordinate slot release, discovery, and admission so overlapping completions and wake-ups cannot strand work or exceed the cap.

## Successful processing

1. Claim an eligible Account Outbox row in an Account Store transaction and keep that transaction open during processing. Its row lock lasts while the transaction remains valid.
2. Check for already-committed recommendations. If present, proceed directly to source completion. Otherwise, calculate the batch and commit its recommendations and Recommendation Outbox row together in a separate local Recommendation Store transaction.
3. Mark the Account Outbox processed and commit the Account transaction, releasing the claim.

No proactive Account claim-loss detection or claim-validity check is required before writing recommendations. Recommendation Store uniqueness prevents competing workers from committing multiple results for the same batch.

## Temporary database failures

Use the existing bounded operation retries. After exhaustion, check the affected store's connectivity every five seconds by default, then resume the pending operation when connectivity returns. These are connectivity checks, not outbox scans.

- While recommendation storage remains unconfirmed, retain the calculated result and worker slot. Keep the Account transaction open while it remains usable.
- After recommendations have committed, retry only the pending Account completion update in an Account Store transaction. This requires neither reclaiming the batch nor recalculating or resubmitting stored recommendations.
- One worker's recovery does not pause admission for other workers. Admission remains subject to the cap and the ability to discover and claim work in the Account Store.

## Unexpected rule-engine exceptions

Catch and log unexpected non-temporary rule-engine exceptions. Store the exception's type, message, and stack trace as structured JSON in a nullable SQL text column named `error`. Write the error in the valid Account claim transaction, leave `processed = false`, and commit. The worker then finishes and releases its claim and slot.

If the Account Store is unavailable before the error is saved, retain the unsaved error and worker slot through connectivity recovery. If the original claim transaction was lost, attempt to reclaim the same batch only if it is still eligible before applying the retained error. If another worker owns the batch, discard the unsaved error and finish. If recommendations already committed, complete the source instead of recording the retained error. This recovery concerns an unsaved error, not a stored recommendation result.

An error keeps its batch excluded from discovery across restarts. Manually clear `error` to restore eligibility for the next startup, wake-up, or completion-triggered scan.
