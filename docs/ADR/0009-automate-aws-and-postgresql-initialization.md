# Automate AWS and PostgreSQL initialization

The deployment must reproduce the complete application from a fresh Windows computer and an empty AWS environment. Required tools and authorized AWS access are prerequisites; AWS resources, database structures, credentials, and privileges require no manual setup.

Retain the existing Terraform backend bootstrap. Terraform owns AWS infrastructure and credentials, using RDS-managed master credentials for `pricinguser` and ephemeral values with write-only arguments for other PostgreSQL passwords. Passwords must not enter Terraform state.

The Pricing Engine owns initialization of `pricingdb`, `accountdb`, and `recommendationdb`: ensuring databases and login roles exist, running all three stores' Flyway migrations, and assigning permissions. Move Backend and Mock Server migrations into the Engine and disable their Flyway execution. Initialization uses privileged credentials; normal operations use restricted accounts without migration privileges. Remove the separate database-init ECS task. Other application services start only after initialization succeeds.

This ownership follows the Engine's existing connections to all three stores; the Backend connects only to the configuration store. Runtime grants are:

| Runtime user | Database | Permissions |
|---|---|---|
| Backend restricted login | `pricingdb` | SELECT, INSERT, UPDATE, DELETE on configuration tables; required sequence access |
| Mock Server restricted login | `accountdb` | INSERT and SELECT on Account Store tables; required sequence access |
| `pricingdb_engine` | `pricingdb` | SELECT on the 15 business tables |
| `accountdb_engine` | `accountdb` | SELECT on `accounts`, `account_attributes`, `fee_requests`, `batch_outbox`; UPDATE on `batch_outbox` |
| `recommendationdb_engine` | `recommendationdb` | INSERT and SELECT on all Recommendation Store tables; required sequence access |
| `recommendationdb_txn_processor` | `recommendationdb` | SELECT on `recommendation_outbox`, `account_recommendations`, `fee_request_recommendations`, `recommendation_eligibility_reasons`; UPDATE on `recommendation_outbox` |

Backend and Mock Server runtime logins do not own schemas or run migrations.

Existing database data and credentials need no preservation. Choose the simplest treatment; neither retaining nor deleting them is a requirement.

The Engine initializes on every startup before becoming ready. Deployment waits for Engine readiness before starting other application services. Ordinary redeployments may stop services during initialization. If initialization fails, deployment stops, services remain stopped, and provisioned resources remain available for a corrected rerun; do not automatically roll back schemas. Local containers use the same Engine-owned initialization and migration path as AWS.

Include Flyway-managed immutability triggers in this work. Allow inserts but reject UPDATE, DELETE, and TRUNCATE on `accounts`, `account_attributes`, `fee_requests`, `account_recommendations`, `fee_request_recommendations`, and `recommendation_eligibility_reasons`. Both `batch_outbox` and `recommendation_outbox` reject DELETE, TRUNCATE, and changes to `batch_id`, without role-based exceptions. Other columns retain the handoff's table-wide UPDATE grants, including future columns.

Engine readiness means database initialization succeeded; pending work and downstream service availability do not block readiness. Existing delivery retry behavior remains unchanged. Retry extensions and transaction-processor implementation are outside this deployment work; provision the processor's database role from the handoff.

No manual CloudShell operations or separate database-init ECS task are required. Verification must cover fresh deployment, a repeat deployment, initialization failure and corrected rerun, runtime grants, and the agreed immutability rules in local containers and AWS.

Design-interview decisions are recorded; shared-understanding confirmation is pending. Implementation has not started.
