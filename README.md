# Pricing App

## Table of contents

- Overview
- Installation
- Configuring Fees
- Simulator
- Architecture
- AWS Infrastructure

## Overview

To be filled out.

## Installation

Clone this repo.

Clone the two repos with front end and back end servers
- https://github.com/DerekThree/pricing-dashboard.git
- https://github.com/DerekThree/pricing-backend.git

There are three ways to run the app
- Local without Docker
- Local with Docker
- AWS

### 1. Local without Docker

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
Open **http://localhost:5173**. The backend runs at **http://localhost:8080**.

### 2. Local with Docker

Requires **Docker Desktop** running.

#### Using powershell script

```powershell
.\setup.ps1
```
Option 2.

#### Manually

**Terminal 1 — Dashboard**

```powershell
cd pricing-dashboard
docker build -t pricing-dashboard .
docker run -p 5173:5173 pricing-dashboard
```

**Terminal 2 — Backend**

```powershell
cd pricing-backend
docker build -t pricing-backend .
docker compose up
```

Open **http://localhost:5173**. The backend runs at **http://localhost:8080**.

### 3. AWS

Requires **AWS CLI**, **Terraform**, **Docker Desktop**, access to AWS **us-east-1**, and the existing S3 Terraform state bucket `pricing-app-tfstate`.

```powershell
.\setup.ps1
```

Select **3 — Start app in AWS** and review/approve the Terraform plans. The script provisions RDS, ECR, ECS, and the load balancer, and publishes Docker images.

To open the deployed dashboard:

```powershell
$alb = terraform -chdir=infra output -raw alb_dns_name
Start-Process "http://$alb"
```
