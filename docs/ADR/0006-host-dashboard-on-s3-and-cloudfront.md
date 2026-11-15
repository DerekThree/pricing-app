# Host Dashboard on S3 and CloudFront

## Status

Accepted

## Context

The client-only React Dashboard builds to static files but runs in an ECS Fargate container.
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

Issue 01 adds independently verifiable static hosting and a publishing function in deploy/setup.ps1.
Existing ECS hosting and API exposure remain during this slice. Static-site same-origin API paths
are unavailable until the API routing cutover; loading static files does not verify API access.
Later migration issues replace Dashboard container delivery and remove its ECS hosting.
Backend exposure is tracked separately in ADR 0007.
