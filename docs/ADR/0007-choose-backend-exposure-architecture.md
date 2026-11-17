# Choose how to expose the ECS backend

## Status

Accepted

## Context

The Dashboard uses private S3 hosting through CloudFront. The Backend and Mock Account Processor
need same-origin HTTPS API access while retaining their existing ECS target groups and path rules.

## Options Considered

- **Keep ALB.** Existing ECS integration and deployment health checks; hourly ALB cost.
- **Use API Gateway.** Request-based pricing and managed API endpoint; requires additional integration and service-discovery configuration to reach ECS privately.
- **Expose ECS directly with DNS updates.** Avoids ALB and API Gateway charges; needs automation for changing task IPs, public backend reachability, and handling deployment interruptions.

## Decision

Use the existing ALB resource as one internal HTTP ALB in the two existing private subnets.
Replacement and temporary downtime are acceptable. Connect it to the Dashboard's existing
CloudFront distribution through one VPC origin, using private HTTP on port 80. Do not add an
ALB, NAT gateway, VPC, or move ECS tasks to different subnets.

Keep S3 as the default origin. Route the existing `/api/*` paths to the ALB with all HTTP methods
enabled, the managed CachingDisabled cache policy, and the managed AllViewer origin request policy.
Forward query strings, request bodies, viewer headers (including authorization and WebSocket
handshake headers), and cookies; preserve response headers including Set-Cookie. Set supported
CloudFront error-cache TTLs to zero without remapping status codes or response pages.

Keep `/api/v1/mock/*` at ALB priority 1 and `/api/*` at priority 2. Return a plain 404 for unmatched
requests; the default listener action must not depend on the Dashboard target group.
Remove the obsolete Dashboard ECS service/task definition and target group.
Restrict ALB port 80 ingress to the AWS-managed CloudFront origin-facing prefix list, removing
the owner-IP allowlist. Retain existing ALB-to-ECS security-group references and health checks.

The same non-cached forwarding policies support future authentication and WSS requests.
When those features define paths outside `/api/*`, add explicit ALB behaviors using these policies;
this decision does not define paths, issue cookies, implement authentication, or add WebSocket code.

## Rationale

This keeps existing ECS integration and routing while providing one HTTPS browser origin and
removing public ALB reachability. CloudFront VPC origins support WebSockets with AllViewer
forwarding; see the [AWS announcement](https://aws.amazon.com/about-aws/whats-new/2026/05/amazon-cloudfront-websockets-vpc-origins/).

## Consequences

The ALB and VPC origin exist only while `alb_enabled` is true. Stop first disables `api_enabled`
to detach the distribution's ALB origin and API behavior while keeping the ALB and VPC origin.
Terraform waits for that distribution update to deploy before the next apply deletes the VPC
origin and ALB. ECS drains before RDS stops. Start recreates the private ingress resources,
reattaches API routing and waits for CloudFront deployment and ECS readiness. The same static
distribution, hostname, bucket and published files remain throughout routine Stop/Start.
Full Destroy removes these resources in dependency order; rebuilding may change the hostname.
Dashboard ECS hosting is retired. RDS, Engine, Cloud Map wake-ups,
and ECS subnet placement retain their existing conventions. The Dashboard hosting decision is
documented separately in ADR 0006.

The ALB incurs hourly and capacity charges only while running. The retained CloudFront
distribution and S3 bucket still incur their applicable usage and storage charges while stopped.
CloudFront HTTPS alone does not authorize API callers. Recruiter-access launch is incomplete
until the separately ticketed magic-link authentication feature protects both browser-facing
APIs. Migration evidence and outstanding findings are recorded in
[ticket 06](../../.scratch/1-cloudfront-internal-alb/issues/06-verify-migration-and-update-adrs.md).
