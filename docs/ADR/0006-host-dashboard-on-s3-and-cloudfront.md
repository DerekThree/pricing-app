# Host Dashboard on S3 and CloudFront

## Status

Proposed

## Context

The React Dashboard builds to static files but currently runs in an ECS Fargate container. We are considering S3 and CloudFront to reduce always-on compute costs and serve the Dashboard over HTTPS.

## Options Considered

- **Keep Dashboard on ECS behind ALB.** Existing deployment and IP restriction; requires a running Fargate task and ALB.
- **Serve Dashboard from private S3 through CloudFront.** Removes Dashboard compute, provides HTTPS and CDN delivery; requires static deployment, SPA route handling, and a different IP-filtering mechanism if IP-only access remains necessary.

## Decision

Pending.

## Rationale

Evaluate deployment simplicity, ongoing cost, and access restrictions before choosing.

## Consequences

If adopted, replace Dashboard ECS deployment with S3 uploads and CloudFront configuration. Backend hosting and exposure are separate decisions (ADR 0007).
