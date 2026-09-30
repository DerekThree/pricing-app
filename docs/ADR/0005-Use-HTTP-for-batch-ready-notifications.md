# Use HTTP "batch ready" notification

## Status

Accepted but unimplemented

## Context

The Account Processor persists account batches in PostgreSQL before notifying the Pricing Engine, and the Pricing Engine persists recommendation batches in PostgreSQL before notifying the Transaction Processor. In both cases, the downstream service processes records that already exist in the database rather than receiving the business records in the notification itself.

The architecture therefore needs a mechanism for telling a downstream service that new persisted work is available. The mechanism must be evaluated against the fact that the persisted batches survive service outages and that a consumer may need to recover unprocessed work after restarting.

The decision must determine whether this handoff requires a durable messaging system or only a direct notification, and whether the notification should identify a particular batch or simply indicate that new work may be available.

## Options Considered

### Apache Kafka

Kafka would publish batch-ready events to durable topics and allow consumers to process them independently.

- **Benefits:**
  - Durable event retention and replay.
  - Strong support for multiple independent consumers and event-stream processing.
  - Useful event history for message-level tracing and audit scenarios.
  - Consumer groups provide scalable consumption.
- **Costs:**
  - Adds broker, topic, partition, retention, monitoring, and operational concerns.
  - Its event-log and replay capabilities are not required if PostgreSQL already preserves the actual pending work.
  - More infrastructure than the current producer-consumer relationships justify.

### Amazon SQS Standard

SQS would place a message on a managed durable queue for each notification boundary.

- **Benefits:**
  - Managed AWS service with little broker infrastructure to operate.
  - Durable buffering while a consumer is unavailable.
  - Natural retry, visibility-timeout, and dead-letter-queue behavior.
  - Simpler operational model than Kafka.
- **Costs:**
  - Adds a messaging service even though PostgreSQL already durably records which batches remain unprocessed.
  - Requires queue configuration and consumer behavior for visibility timeout, retries, retention, and dead-letter handling.
  - If the queue message is only a wake-up signal, durable message retention duplicates durability already provided by PostgreSQL.

### RabbitMQ

RabbitMQ could provide durable queues and acknowledgment-based message delivery.

- **Benefits:**
  - Mature traditional message-broker model.
  - Flexible routing and delivery configuration.
  - Supports durable queues and retry-oriented processing.
- **Costs:**
  - Introduces broker infrastructure and operational responsibility without a routing requirement that justifies it.
  - Provides capabilities beyond what is needed for a generic work-available signal.

### Amazon EventBridge

EventBridge could publish a work-available event and route it to one or more downstream targets.

- **Benefits:**
  - Managed event routing.
  - Supports future fan-out to multiple targets and rule-based routing.
  - Integrates naturally with other AWS services.
- **Costs:**
  - The current architecture does not require many-to-many event routing or rule-based distribution.
  - Adds another infrastructure layer when each notification currently has one intended downstream service.

### HTTP notification

The producer could call the downstream service and identify the specific persisted batch that became ready.

- **Benefits:**
  - Simple request-response integration with no message broker.
  - Lets the consumer immediately process the batch.
  - Keeps the notification small while still identifying the work directly.
- **Costs:**
  - producer needs to check whether the request was received and try again or in some other way react to the filure.
  - HTTP itself does not buffer notifications while the consumer is unavailable.
  - The consumer must own reliable discovery and processing state in PostgreSQL.

## Decision

Use **HTTP notification** for both notification boundaries.

The notification does not contain persisted business records or batchId. The downstream service queries PostgreSQL for unprocessed batches and processes the work found there. The service that stores the batch owns publishing the HTTP notification and retrying in case of failure.

**Transactional outbox** remains responsible for recording notification work atomically with the persisted batch. The outbox stores the status of the batch, allowing consumers to identify batches that haven't been processed. 

PostgreSQL is the durable source of pending work. Consumers also **query for unprocessed batches on startup or restart**, so recovery does not depend on preserving notification messages while the consumer is unavailable.

## Rationale

The notification does not need durable message semantics because the business work itself is already durably persisted and discoverable in PostgreSQL. A message broker would duplicate part of that durability while adding infrastructure and operational concerns.

HTTP is sufficient because the notification is intentionally weak: it means only that the consumer should check PostgreSQL. The consumer does not rely on the request to identify, contain, or preserve the work. This keeps the transport simple while retaining crash recovery through persisted processing state and outbox check on startup.

## Consequences

- PostgreSQL must represent enough processing state for consumers to identify unprocessed batches safely.
- The Pricing Engine and Transaction Processor must check for unprocessed work on startup or restart.
- HTTP endpoint and request-response details still need to be defined.
- Duplicate notofications are acceptable and should not create duplicate business results.
- Batch-processing idempotency is resolved by maintaining batch status in DB outbox.
- Kafka, Amazon SQS, RabbitMQ, and EventBridge are not part of the current notification architecture.
- If future requirements introduce durable event history, multiple independent consumers, replay, broker-level buffering, or complex event routing, the messaging decision can be revisited.
