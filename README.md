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

Requires **Java 21**, **Node.js/npm**, and **PostgreSQL** on port 5432. Create
`pricingdb` owned by `pricinguser` and `accountdb` owned by `accountuser`, with separate passwords.

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
$env:SPRING_DATASOURCE_PASSWORD = Read-Host 'Pricing database password'
.\mvnw.cmd spring-boot:run
```

**Terminal 3 — Mock Processor**

```powershell
cd .\pricing-mock-server
$env:SPRING_DATASOURCE_URL = 'jdbc:postgresql://localhost:5432/accountdb'
$env:SPRING_DATASOURCE_USERNAME = 'accountuser'
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
The Dashboard retains its runtime `API_URL=http://localhost:8080` configuration.

PostgreSQL creates `pricingdb`/`pricinguser`. `deploy/local/init-db.sh` creates
`accountdb`/`accountuser` in the same container. Each application runs its own Flyway migrations.
The initialization script runs automatically only when the PostgreSQL data volume is empty.
To discard local database data and initialize again:

```powershell
docker compose --env-file deploy/local/.env -f deploy/local/compose.yaml down --volumes
docker compose --env-file deploy/local/.env -f deploy/local/compose.yaml up --build
```

Both Java applications expose `/actuator/health`, including database connectivity, without
internal details. Compose waits for PostgreSQL initialization before starting the Java services
and waits for their health checks before starting the Dashboard.
Shell scripts use LF line endings through `.gitattributes`.

### AWS

Requires **AWS CLI**, **Terraform**, and **Docker Desktop**.

```powershell
.\deploy\setup.ps1
```

Terraform configuration lives in `deploy/aws/`; S3 state configuration lives in
`deploy/aws/bootstrap/`. The script prepares RDS, ECR, and a database initialization task,
builds and pushes the three application images, and runs the initialization task on Fargate.
The task runs `deploy/local/init-db.sh` using `psql` against the existing RDS instance.
ECS injects the RDS and Account Store passwords from Secrets Manager. The local PostgreSQL
container and its automatic initialization hook are not deployed to AWS.

The script waits for the task to stop, checks its container exit code, then applies the started
configuration for all three ECS services and the ALB. A stopped task is successful only when its
container exit code is zero. Task logs are in the `database-init` stream prefix of `/ecs/pricing-app`.

Passwords are supplied to Terraform only when initially creating their database/secret value.
Later start/stop operations retain those values without extracting and resupplying passwords.
The database initialization task reads its credentials through ECS Secrets Manager injection.

Open the web address printed by the script. Stop drains all three application services before
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
- Both Java target groups and ECS container health checks use `/actuator/health`.
- Each application has its own security group. RDS permits PostgreSQL connections from
  the Backend, Mock Processor, and database initialization task security groups.

### Containers and database initialization

- ECR repositories: `pricing-backend`, `pricing-dashboard`, and `pricing-mock-server`.
- ECS cluster: `pricing-app-cluster`, with a Fargate task definition and service for each application.
- One-off Fargate task: `pricing-database-init`, using the PostgreSQL client to create
  `accountuser` and `accountdb` when they do not already exist.
- RDS instance: `pricing-app-db`, hosting `pricingdb` and `accountdb` with separate logins/passwords.
- Each application owns its schema migrations through Flyway.
- CloudWatch log group: `/ecs/pricing-app`, with application and `database-init` stream prefixes.

### Credentials and state

- Secrets Manager stores `pricing-app/rds-password` and `pricing-app/account-password`.
- The ECS execution role reads these secrets and injects the required password into each container.
- Terraform's secret-version resources retain their existing values after initial creation.
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
