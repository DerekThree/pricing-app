# Pricing App

## Table of contents

- [Overview](#overview)
- [Installation](#installation)
- [Configuring Fees](#configuring-fees)
- [Simulator](#simulator)
- [Architecture](#architecture)
- [AWS Infrastructure](#aws-infrastructure)

## Overview

To be filled out.

## Installation

Clone the main repo.
- https://github.com/DerekThree/pricing-app.git

Clone the three application repositories in the main repository folder
- https://github.com/DerekThree/pricing-dashboard.git
- https://github.com/DerekThree/pricing-backend.git
- https://github.com/DerekThree/pricing-mock-server.git

There are three ways to run the app
- [Local without Docker](#1-local-without-docker)
- [Local with Docker](#2-local-with-docker)
- [AWS](#3-aws)

### Local without Docker

Requires **Java 21**, **Node.js/npm**, and **PostgreSQL** on port 5432 with `pricingdb` created.
Start the Engine first to create `accountdb` and `recommendationdb` and initialize all three stores.
Initialization reuses the Pricing Store's `spring.datasource.url`;
`INITIALIZATION_USERNAME` and `INITIALIZATION_PASSWORD` provide the separate privileged login
for database/login creation, Flyway migrations, and grants. Runtime logins are separate.
The Engine provisions Mock Server's login using `ACCOUNT_STORE_MOCK_SERVER_USERNAME`
(default `accountdb_mock_server`) and `ACCOUNT_STORE_MOCK_SERVER_PASSWORD`; Mock Server uses
the matching datasource credentials below.

**Terminal 1 — Dashboard**

```powershell
cd .\pricing-dashboard
npm ci
npm run dev
```

**Terminal 2 — Backend**

```powershell
cd .\pricing-backend
$env:SPRING_DATASOURCE_URL = 'jdbc:postgresql://localhost:5432/pricingdb'
$env:SPRING_DATASOURCE_USERNAME = 'pricinguser'
$env:SPRING_DATASOURCE_PASSWORD = Read-Host 'Pricing Store password'
.\mvnw.cmd spring-boot:run
```

**Terminal 3 — Mock Processor**

```powershell
cd .\pricing-mock-server
$env:SPRING_DATASOURCE_URL = 'jdbc:postgresql://localhost:5432/accountdb'
$env:SPRING_DATASOURCE_USERNAME = 'accountdb_mock_server'
$env:SPRING_DATASOURCE_PASSWORD = Read-Host 'Account database password'
.\mvnw.cmd spring-boot:run
```

Open **http://localhost:5173**.

### Local with Docker

Requires **Docker Desktop** running. One Compose file starts PostgreSQL, the Backend,
the Mock Processor, and the Dashboard.

#### Using PowerShell

From the main repository:

```powershell
.\deploy\setup.ps1
```

Choose **Start app in local Docker**. The script generates separate database passwords in
`deploy/local/.env`, builds the application images, and opens one terminal with the Compose logs.
On the first run after conversion, it replaces the old separately managed application containers.
The shared Compose project uses a new PostgreSQL volume; the old volume is not reused.

#### Manually

Copy the example, then set separate passwords in the new file:

```powershell
Copy-Item .\deploy\local\.env.example .\deploy\local\.env
docker compose --env-file deploy/local/.env -f deploy/local/compose.yaml up --build
```

The Dashboard is at **http://localhost:5173**, Backend at **http://localhost:8080**, and
Mock Processor at **http://localhost:8081**. PostgreSQL exposes port **5432**.
The Dashboard uses browser-visible runtime `BACKEND_API_URL=http://localhost:8080` and
`ACCOUNT_PROCESSOR_API_URL=http://localhost:8081` settings.

PostgreSQL creates `pricingdb` and the privileged `pricinguser` login. On every startup,
the Engine reuses the Pricing Store URL with that login to create `accountdb` and
`recommendationdb`, run all three stores' Flyway migrations, and grant the separate runtime
logins their permissions. Backend and Mock Server production Flyway are disabled.
Set all seven passwords from `.env.example` in `.env`;
only `POSTGRES_PASSWORD` belongs to the privileged initialization login.
To discard local database data and initialize again:

```powershell
docker compose --env-file deploy/local/.env -f deploy/local/compose.yaml down --volumes
docker compose --env-file deploy/local/.env -f deploy/local/compose.yaml up --build
```

Backend and Mock Server expose `/actuator/health`, including database connectivity, without
internal details. Compose starts the Engine after PostgreSQL is healthy, then waits for its
`/openapi.yaml` readiness before starting the other application services. Initialization failure
leaves dependent services stopped and database changes in place for a corrected rerun. Pending
processing and downstream availability do not block Engine readiness. The Dashboard also waits
for Backend and Mock Server health checks.
Shell scripts use LF line endings through `.gitattributes`.

### AWS

Requires **AWS CLI**, **Terraform**, and **Docker Desktop**.

```powershell
.\deploy\setup.ps1
```

Terraform configuration lives in `deploy/aws/`; S3 state configuration lives in
`deploy/aws/bootstrap/`. Start returns without changes when the application is already running.
Otherwise, it prepares RDS, infrastructure and credentials, then builds and pushes all four
application images while preserving existing service counts. It starts Engine and checks
the expected task revision is healthy through `/openapi.yaml` before starting other stopped
application services. If initialization fails, resources and previously running services are
retained; an Engine newly started by this invocation is stopped. Correct the failure and run
Start again; the script does not correct configuration or roll back schemas. Engine logs use
the `engine` stream prefix in `/ecs/pricing-app`.

RDS manages the `pricinguser` master password in Secrets Manager. Terraform generates other
database passwords with ephemeral values and stores them through write-only secret arguments.
Later start/stop operations retain secret versions without resupplying or rotating passwords.
Setup applies RDS first so its managed master-secret ARN exists before planning consumers.
RDS creates `pricingdb`. Engine reuses the Pricing Store URL with one privileged
initialization login and receives separate restricted runtime passwords through ECS Secrets
Manager injection. It creates `accountdb`, `recommendationdb`, and login roles, runs all three
stores' Flyway migrations, and assigns grants before readiness. Pending processing and unavailable
downstream services do not block initialization readiness.

Open the web address printed by the script. Stop drains all four application services before
stopping the single RDS instance. Destroy removes the managed application infrastructure and data;
the state bucket remains separately managed.

## Configuring Fees

To be filled out.

## Simulator

To be filled out.

## Architecture

To be filled out.

## AWS Infrastructure

Terraform in `deploy/aws/` uses the existing VPC, public subnets for ALB/ECS, and private subnets
for one RDS PostgreSQL instance. The existing ALB HTTP allowlist is retained.

### Routing and health

- The ALB sends `/api/v1/mock/*` to `pricing-mock-server-tg` on port 8081 with priority 1.
- The general `/api/*` rule sends Backend requests to `pricing-backend-tg` on port 8080
  with priority 2.
- Other requests go to `pricing-dashboard-tg` on port 5173.
- Backend and Mock Server use `/actuator/health`; Engine container readiness uses `/openapi.yaml`.
- Each application has its own security group. RDS permits PostgreSQL connections from
  the Backend, Mock Processor, and Engine security groups.

### Containers and database initialization

- ECR repositories: `pricing-backend`, `pricing-dashboard`, `pricing-mock-server`, and `pricing-engine`.
- ECS cluster: `pricing-app-cluster`, with a Fargate task definition and service for each application.
- RDS instance: `pricing-app-db`, hosting `pricingdb`, `accountdb`, and `recommendationdb`.
- RDS creates `pricingdb`; Engine owns creation of `accountdb`, `recommendationdb`, and login roles,
  all three stores' Flyway migrations, and grants. Backend and Mock Server production Flyway
  are disabled.
- CloudWatch log group: `/ecs/pricing-app`, with application stream prefixes including `engine`.

### Credentials and state

- RDS creates and manages its master secret. Terraform manages the Backend, Account and Recommendation
  passwords and the four Engine/transaction-processor role secrets in Secrets Manager.
- The ECS execution role reads these secrets and injects the required password into each container.
- Terraform 1.11+ and the AWS and Random providers support ephemeral password generation and
  write-only secret values; database passwords are excluded from new Terraform state.
- Secret versions remain stable on repeat applies. Increment `secret_string_wo_version` to
  write a new generated password; PostgreSQL role passwords must be updated with it.
- Legacy versions of the versioned S3 state may still contain passwords from before migration.
- The S3 state bucket is `pricing-app-tfstate`, with application state at `terraform.tfstate`
  and state-bucket configuration state at `bootstrap.tfstate`. Moving the local files does not
  change those keys. The bucket retains versioning, encryption, and its public-access block.

### Configuration checks

```powershell
docker compose --env-file deploy/local/.env.example -f deploy/local/compose.yaml config --quiet
terraform -chdir=deploy/aws validate
```

After local startup, check **http://localhost:8080/actuator/health** and
**http://localhost:8081/actuator/health**; both should return `{"status":"UP"}`.
