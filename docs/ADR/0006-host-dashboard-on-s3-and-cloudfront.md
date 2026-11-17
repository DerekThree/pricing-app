# Host Dashboard on S3 and CloudFront

## Status

Accepted

## Context

The client-only React Dashboard builds to static files but previously ran in an ECS container.
Static hosting provides HTTPS without a purchased domain or certificate.

## Options Considered

- **Keep Dashboard on ECS behind ALB.** Existing deployment and IP restriction; requires a running Fargate task and ALB.
- **Serve Dashboard from private S3 through CloudFront.** Removes Dashboard compute, provides HTTPS and CDN delivery; requires static deployment, SPA route handling, and a different IP-filtering mechanism if IP-only access remains necessary.

## Decision

Serve the existing production browser build from a private S3 bucket through one CloudFront
distribution, managed in the existing Terraform root. Block public bucket access and allow
CloudFront reads through Origin Access Control, restricted to the distribution ARN. Use the
AWS-assigned hostname and default certificate, redirecting viewer HTTP to HTTPS.

Rewrite only Dashboard routes to the SPA entry point in a viewer-request CloudFront Function.
Leave API paths and asset requests unchanged; do not use distribution-wide HTML error responses.
Revalidate index.html and config.js, and cache fingerprinted assets for one year.

## Rationale

This serves static files without requiring Dashboard compute and provides a public HTTPS URL.

## Consequences

Dashboard CI publishes its existing browser build as an artifact after typecheck and browser
tests. CD discovers the current distribution and bucket through the existing `dashboard-s3` origin,
so infrastructure recreation requires no manual ID updates. It uses the existing AWS OIDC role
with account-wide distribution-list access and bucket/distribution-scoped publishing permissions,
uploads static assets and same-origin runtime config, and publishes HTML last. It waits for
CloudFront invalidation and verifies every published object's bytes through HTTPS before success.
Dashboard delivery no longer builds an ECR image or requests an ECS rollout.
The publishing function in deploy/setup.ps1 also sets both API base URLs to the browser's origin.
While the ALB is enabled, CloudFront routes `/api/*` through one VPC origin to the existing ALB,
configured as internal in the two existing private subnets. Static requests continue to use S3.
API requests have caching disabled and preserve origin errors rather than returning SPA HTML.
Dashboard ECS service/task definition, ECR repository, ALB target group, and task security group
are removed. Local Dashboard development and Compose retain their existing container build.
Backend exposure and forwarding policy are documented in ADR 0007.

Routine Stop detaches API routing, then removes the VPC origin and internal ALB. It retains
the distribution, its exact HTTPS hostname, the private S3 bucket and published files.
Start restores API connectivity on that same distribution. Explicit full
Destroy removes the distribution and populated bucket; a subsequent full rebuild may issue a
different hostname and invalidate previously distributed URLs, including magic-link URLs.
S3 storage and CloudFront delivery remain billable while stopped; Dashboard ECS and ECR hosting
costs are removed.
