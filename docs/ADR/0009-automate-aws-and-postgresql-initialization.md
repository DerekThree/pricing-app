# Automate AWS and PostgreSQL initialization

The deployment must reproduce the complete application from a fresh Windows computer and an empty AWS environment. Required tools and authorized AWS access are prerequisites; AWS resources, database structures, credentials, and privileges require no manual setup.

Retain the existing Terraform backend bootstrap. Terraform owns AWS infrastructure and credentials, using RDS-managed master credentials for `pricinguser` and ephemeral values with write-only arguments for other PostgreSQL passwords. Passwords must not enter Terraform state.

The Pricing Engine owns initialization of `pricingdb`, `accountdb`, and `recommendationdb`: ensuring databases and login roles exist, running all three stores' Flyway migrations, and assigning permissions. Move Backend and Mock Server migrations into the Engine and disable their Flyway execution. Initialization uses one shared privileged `pricinguser` login for database/login creation, Flyway migrations, and grants across all three databases; normal operations use restricted accounts without migration privileges. Remove the separate database-init ECS task. Other application services start only after initialization succeeds.

This ownership follows the Engine's existing connections to all three stores; the Backend connects only to the Pricing Store. Runtime grants are:

| Runtime user | Database | Permissions |
|---|---|---|
| Backend restricted login | `pricingdb` | SELECT, INSERT, UPDATE, DELETE on Pricing Store tables; required sequence access |
| Mock Server restricted login | `accountdb` | INSERT and SELECT on Account Store tables; required sequence access |
| `pricingdb_engine` | `pricingdb` | SELECT on the 15 business tables |
| `accountdb_engine` | `accountdb` | SELECT on `accounts`, `account_attributes`, `fee_requests`, `batch_outbox`; UPDATE on `batch_outbox` |
| `recommendationdb_engine` | `recommendationdb` | INSERT and SELECT on all Recommendation Store tables; required sequence access |
| `recommendationdb_txn_processor` | `recommendationdb` | SELECT on `recommendation_outbox`, `account_recommendations`, `fee_request_recommendations`, `recommendation_eligibility_reasons`; UPDATE on `recommendation_outbox` |

Backend and Mock Server runtime logins do not own schemas or run migrations.

Existing database data and credentials need no preservation. Choose the simplest treatment; neither retaining nor deleting them is a requirement.

The Engine initializes on every startup before becoming ready, reusing the Pricing Store URL
with privileged initialization credentials. RDS or local PostgreSQL creates `pricingdb`. Engine
creates the other two databases. Local containers use the same Engine-owned initialization and
migration path as AWS.

AWS Start leaves an already-running application unchanged. With the state bucket in place,
one Terraform apply provisions infrastructure and credentials, creates or resumes RDS, and
preserves each ECS service's desired count. PowerShell dispatches CD for the recorded Engine
`main` commit and waits for the resulting ECS deployment to become healthy before dispatching
CD for the other three repositories. CD reuses images from ECR or publishes CI-built images.
Explicit Start authorizes CD to raise a stopped service's desired count to one. A push to
`main` publishes the image and redeploys the service only when its desired count is positive.

If initialization fails, startup retains resources and previously running services. Start stops
an Engine it newly started when it can identify the failed deployment or its rollback. If the
deployment ID is unavailable, Start reports the failure before dispatching the other services.

AWS Stop uses one full Terraform apply to scale ECS services to zero, remove the ALB and DNS
alias, and stop RDS. ECS scale-down and RDS shutdown can run in parallel.

Include Flyway-managed immutability triggers in this work. Allow inserts but reject UPDATE, DELETE, and TRUNCATE on `accounts`, `account_attributes`, `fee_requests`, `account_recommendations`, `fee_request_recommendations`, and `recommendation_eligibility_reasons`. Both `batch_outbox` and `recommendation_outbox` reject DELETE, TRUNCATE, and changes to `batch_id`, without role-based exceptions. Other columns retain the handoff's table-wide UPDATE grants, including future columns.

Engine readiness means database initialization succeeded; pending work and downstream service availability do not block readiness. Existing delivery retry behavior remains unchanged. Retry extensions and transaction-processor implementation are outside this deployment work; provision the processor's database role from the handoff.

No manual CloudShell operations or separate database-init ECS task are required. Verification must cover fresh deployment, startup with existing databases, the already-running no-op, initialization failure and corrected rerun, runtime grants, and the agreed immutability rules in local containers and AWS.

## Verification

The original initialization verification is recorded in the tickets. The revised Start and
Stop flow, including fresh AWS provisioning and GitHub Actions dispatch, awaits user testing.
