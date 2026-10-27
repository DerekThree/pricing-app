# Choose how to expose the ECS backend

## Status

Proposed

## Context

Spring Boot runs as a single ECS Fargate service. An ALB currently provides a stable endpoint and limits inbound traffic to the owner's IP. If the Dashboard moves to CloudFront, the backend still needs a reliable HTTPS-accessible route for API requests.

## Options Considered

- **Keep ALB.** Existing ECS integration and deployment health checks; hourly ALB cost.
- **Use API Gateway.** Request-based pricing and managed API endpoint; requires additional integration and service-discovery configuration to reach ECS privately.
- **Expose ECS directly with DNS updates.** Avoids ALB and API Gateway charges; needs automation for changing task IPs, public backend reachability, and handling deployment interruptions.

## Decision

Pending.

## Rationale

Compare cost, security, endpoint stability, and operational complexity for one low-traffic backend service.

## Consequences

The selected approach will determine ECS networking, API routing from CloudFront, and deployment health checks. The Dashboard hosting decision is documented separately in ADR 0006.
