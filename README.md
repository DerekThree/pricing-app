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

Clone the two repos, with front end and back end servers, in the main folder of the main repo
- https://github.com/DerekThree/pricing-dashboard.git
- https://github.com/DerekThree/pricing-backend.git

There are three ways to run the app
- [Local without Docker](#1-local-without-docker)
- [Local with Docker](#2-local-with-docker)
- [AWS](#3-aws)

### Local without Docker

Requires **Java 21**, **Node.js/npm**, and **PostgreSQL installed and running locally** on port 5432. Create the PostgreSQL database `pricingdb` and user `pricinguser`, and set a password for that user.



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
$env:SPRING_DATASOURCE_PASSWORD = Read-Host 'PostgreSQL password'
.\mvnw.cmd spring-boot:run
```
Open **http://localhost:5173**.

### Local with Docker

Requires **Docker Desktop** running.
You can do it [using powershell script](#using-powershell-script) or [manually](#manually)

#### Using powershell script

```powershell
.\setup.ps1
```
Open **http://localhost:5173**.

#### Manually

Create `pricing-backend/.env` from the example and set `POSTGRES_PASSWORD` in the new file:

```powershell
Copy-Item .\pricing-backend\.env.example .\pricing-backend\.env
```

Terminal 1 — Dashboard

```powershell
cd pricing-dashboard
docker build -t pricing-dashboard .
docker run -p 5173:5173 -e API_URL=http://localhost:8080 pricing-dashboard
```

Terminal 2 — Backend

```powershell
cd pricing-backend
docker build -t pricing-backend .
docker compose up
```

Open **http://localhost:5173**.

### AWS

Requires **AWS CLI**, **Terraform**, and **Docker Desktop**.

```powershell
.\setup.ps1
```
##### The script provisions RDS, ECR, ECS, ALB, and publishes Docker images.
Open the privided web address.

## Configuring Fees

To be filled out.

## Simulator

To be filled out.

## Architecture

To be filled out.

## AWS Infrastructure

The application infrastructure is managed with Terraform in AWS. The following sections cover all 35 configured resource blocks, grouped by purpose.

### Networking and traffic routing

- **VPC**: `pricing-app-vpc` — Application virtual private cloud.
- **Internet gateway**: `pricing-app-igw` — Internet access for public subnets.
- **Public subnets**: `pricing-app-public-a`, `pricing-app-public-b` — Subnets used by the load balancer and ECS tasks.
- **Private subnets**: `pricing-app-private-a`, `pricing-app-private-b` — Subnets used by RDS.
- **Public route table**: `pricing-app-public-rt` — Routes public-subnet internet traffic through the internet gateway.
- **Route table associations**: `pricing-app-public-a` and `pricing-app-public-b` to `pricing-app-public-rt` — Attach the public route table to the public subnets.
- **Backend target group**: `pricing-backend-tg` — Health checks and routing to backend tasks.
- **Dashboard target group**: `pricing-dashboard-tg` — Health checks and routing to dashboard tasks.
- **Application Load Balancer (ALB)**: `pricing-app-alb` — Entry point for web and API requests.
- **HTTP listener**: `pricing-app-alb` (HTTP port 80) — Routes normal web requests to the dashboard.
- **API listener rule**: `pricing-app-alb` (`/api/*`) — Routes API requests to the backend.

### Network access and security groups

- **ALB security group**: `pricing-app-alb-sg` — Restricts incoming access to the load balancer.
- **Backend security group**: `pricing-app-backend-sg` — Permits backend traffic from the ALB.
- **Dashboard security group**: `pricing-app-dashboard-sg` — Permits dashboard traffic from the ALB.
- **Database security group**: `pricing-app-rds-sg` — Permits PostgreSQL traffic from the backend.

### Containers and compute

- **Backend ECR repository**: `pricing-backend` — Stores the backend Docker image.
- **Dashboard ECR repository**: `pricing-dashboard` — Stores the dashboard Docker image.
- **ECS cluster**: `pricing-app-cluster` — Groups the application services.
- **Backend task definition**: `pricing-backend` — Defines the backend Fargate container.
- **Dashboard task definition**: `pricing-dashboard` — Defines the dashboard Fargate container.
- **Backend ECS service**: `pricing-backend-service` — Runs and manages backend tasks.
- **Dashboard ECS service**: `pricing-dashboard-service` — Runs and manages dashboard tasks.

### Database

- **DB subnet group**: `pricing-app-db-subnet-group` — Specifies the private subnets for the database.
- **RDS PostgreSQL instance**: `pricing-app-db` — Stores application data.

### Database credentials and IAM

- **Secrets Manager secret**: `pricing-app/rds-password` — Holds the database password.
- **Secret version**: `pricing-app/rds-password` (version) — Stores the password value.
- **ECS task execution role**: `ecsTaskExecutionRole` — Role used by ECS when starting tasks.
- **Execution policy attachment**: `AmazonECSTaskExecutionRolePolicy` attached to `ecsTaskExecutionRole` — Attaches the standard ECS task execution permissions.
- **Secret-access policy**: `PricingAppReadRdsPassword` — Allows ECS to retrieve the database password.

ECS supplies the stored password to the backend container without embedding it in the Docker image.

### Logs

- **CloudWatch log group**: `/ecs/pricing-app` — Collects backend and dashboard container logs.

### Terraform state and bootstrap

- **S3 state bucket**: `pricing-app-tfstate` — Stores Terraform remote state separately from the application infrastructure.
- **Bucket versioning**: Retains state-object versions.
- **Bucket encryption**: Configures server-side encryption.
- **Public-access block**: Blocks public bucket access.

The S3 state bucket is managed by the separate bootstrap configuration and protected against Terraform destruction. Both Terraform configurations use S3 state locking. Application teardown does **not** destroy the state bucket.
