# Pricing App: reconciled with read-only AWS inventory, 2026-09-29.
# Use deploy/setup.ps1 for ordered lifecycle operations; imports require explicit opt-in.
terraform {
  required_version = ">= 1.7.0"

  backend "s3" {
    bucket       = "pricing-app-tfstate"
    key          = "terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}
provider "aws" { region = var.aws_region }

variable "aws_region" {
  type    = string
  default = "us-east-1"
}
variable "import_existing" {
  description = "Opt in to the retained imports after checking their resource IDs."
  type        = bool
  default     = false
}
variable "rds_password" {
  description = "Database password supplied only during initial creation."
  type        = string
  sensitive   = true
  default     = null
}
variable "allowed_http_cidr" {
  description = "Existing ALB HTTP allowlist; do not widen without explicit authorization."
  type        = string
  default     = "130.105.47.225/32"
}
variable "account_password" {
  description = "Account database password supplied only during initial creation."
  type        = string
  sensitive   = true
  default     = null
}
variable "mock_server_desired_count" {
  type    = number
  default = 0
  validation {
    condition = (
      var.mock_server_desired_count >= 0 &&
      floor(var.mock_server_desired_count) == var.mock_server_desired_count
    )
    error_message = "mock_server_desired_count must be a nonnegative integer."
  }
}
variable "backend_desired_count" {
  type    = number
  default = 0
  validation {
    condition     = var.backend_desired_count >= 0 && floor(var.backend_desired_count) == var.backend_desired_count
    error_message = "backend_desired_count must be a nonnegative integer."
  }
}
variable "dashboard_desired_count" {
  type    = number
  default = 0
  validation {
    condition     = var.dashboard_desired_count >= 0 && floor(var.dashboard_desired_count) == var.dashboard_desired_count
    error_message = "dashboard_desired_count must be a nonnegative integer."
  }
}
variable "alb_enabled" {
  description = "Create ALB, listener and rule during start; destroy them during stop. Target groups persist."
  type        = bool
  default     = false
}
variable "rds_state" {
  description = "Desired RDS instance state: available or stopped."
  type        = string
  default     = "stopped"
  validation {
    condition     = contains(["available", "stopped"], var.rds_state)
    error_message = "rds_state must be available or stopped."
  }
}
locals {
  database_identifier = "pricing-app-db"
  public_subnets = {
    a = { cidr = "10.0.3.0/24", az = "us-east-1a" }
    b = { cidr = "10.0.4.0/24", az = "us-east-1b" }
  }
  private_subnets = {
    a = { cidr = "10.0.1.0/24", az = "us-east-1a" }
    b = { cidr = "10.0.2.0/24", az = "us-east-1b" }
  }
}

resource "aws_vpc" "pricing" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = false
  instance_tenancy     = "default"
  tags                 = { Name = "pricing-app-vpc" }
}
resource "aws_internet_gateway" "pricing" {
  vpc_id = aws_vpc.pricing.id
  tags   = { Name = "pricing-app-igw" }
}
resource "aws_subnet" "public" {
  for_each                = local.public_subnets
  vpc_id                  = aws_vpc.pricing.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = false
  tags                    = { Name = format("pricing-app-public-%s", each.key) }
}
resource "aws_subnet" "private" {
  for_each                = local.private_subnets
  vpc_id                  = aws_vpc.pricing.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = false
  tags                    = { Name = format("pricing-app-private-%s", each.key) }
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.pricing.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.pricing.id
  }
  tags = { Name = "pricing-app-public-rt" }
}
resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}
# Private subnets inherit the VPC main route table (local route only). No NAT.

resource "aws_security_group" "alb" {
  name        = "pricing-app-alb-sg"
  description = "Pricing App load balancer security group"
  vpc_id      = aws_vpc.pricing.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.allowed_http_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_security_group" "backend" {
  name        = "pricing-app-backend-sg"
  description = "Security group for Pricing App backend ECS tasks"
  vpc_id      = aws_vpc.pricing.id
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_security_group" "dashboard" {
  name        = "pricing-app-dashboard-sg"
  description = "Pricing App dashboard security group"
  vpc_id      = aws_vpc.pricing.id
  ingress {
    from_port       = 5173
    to_port         = 5173
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_security_group" "database" {
  name        = "pricing-app-rds-sg"
  description = "Security group for Pricing App PostgreSQL RDS"
  vpc_id      = aws_vpc.pricing.id
  ingress {
    description = "Allow PostgreSQL from Pricing App services and database initialization"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    security_groups = [
      aws_security_group.backend.id,
      aws_security_group.mock_server.id,
      aws_security_group.database_init.id
    ]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_db_subnet_group" "pricing" {
  name        = "pricing-app-db-subnet-group"
  description = "Pricing App RDS subnet group"
  subnet_ids  = [aws_subnet.private["a"].id, aws_subnet.private["b"].id]
}
# Imported databases keep their existing password and secret version.
resource "aws_secretsmanager_secret" "rds_password" {
  name                    = "pricing-app/rds-password"
  recovery_window_in_days = 0
}
resource "aws_secretsmanager_secret_version" "rds_password" {
  count         = 1
  secret_id     = aws_secretsmanager_secret.rds_password.id
  secret_string = jsonencode({ password = var.rds_password })
  lifecycle {
    ignore_changes = [secret_string]
  }
}
resource "aws_db_instance" "pricing" {
  identifier                   = local.database_identifier
  db_name                      = "pricingdb"
  username                     = "pricinguser"
  password                     = var.rds_password
  engine                       = "postgres"
  engine_version               = "18.3"
  instance_class               = "db.t4g.micro"
  allocated_storage            = 20
  max_allocated_storage        = 1000
  storage_type                 = "gp3"
  storage_encrypted            = true
  port                         = 5432
  multi_az                     = false
  publicly_accessible          = false
  db_subnet_group_name         = aws_db_subnet_group.pricing.name
  vpc_security_group_ids       = [aws_security_group.database.id]
  parameter_group_name         = "default.postgres18"
  option_group_name            = "default:postgres-18"
  backup_retention_period      = 0
  backup_window                = "10:10-10:40"
  maintenance_window           = "tue:07:25-tue:07:55"
  auto_minor_version_upgrade   = true
  performance_insights_enabled = true
  monitoring_interval          = 0
  copy_tags_to_snapshot        = true
  deletion_protection          = false
  skip_final_snapshot          = true
  lifecycle {
    ignore_changes = [password]
  }
  depends_on = [aws_secretsmanager_secret_version.rds_password]
}
resource "aws_rds_instance_state" "pricing" {
  # Independent so a targeted start cannot modify a stopped database first.
  # deploy/setup.ps1 creates the database before applying this controller.
  identifier = local.database_identifier
  state      = var.rds_state
}
resource "aws_ecr_repository" "backend" {
  name                 = "pricing-backend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_scanning_configuration { scan_on_push = false }
  encryption_configuration { encryption_type = "AES256" }
}
resource "aws_ecr_repository" "dashboard" {
  name                 = "pricing-dashboard"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_scanning_configuration { scan_on_push = false }
  encryption_configuration { encryption_type = "AES256" }
}
resource "aws_cloudwatch_log_group" "pricing" {
  name              = "/ecs/pricing-app"
  retention_in_days = 3
}
resource "aws_iam_role" "execution" {
  name = "ecsTaskExecutionRole"
  assume_role_policy = jsonencode({
    Version = "2008-10-17"
    Statement = [{
      Sid       = ""
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "execution_base" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_iam_role_policy" "execution_secret" {
  name = "PricingAppReadRdsPassword"
  role = aws_iam_role.execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "secretsmanager:GetSecretValue"
      Resource = [
        aws_secretsmanager_secret.rds_password.arn,
        aws_secretsmanager_secret.account_password.arn
      ]
    }]
  })
}
resource "aws_ecs_cluster" "pricing" {
  name = "pricing-app-cluster"
  configuration {
    execute_command_configuration { logging = "DEFAULT" }
  }
  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}
resource "aws_lb" "pricing" {
  count              = var.alb_enabled ? 1 : 0
  name               = "pricing-app-alb"
  internal           = false
  load_balancer_type = "application"
  ip_address_type    = "ipv4"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public["a"].id, aws_subnet.public["b"].id]
}
resource "aws_lb_target_group" "backend" {
  name        = "pricing-backend-tg"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.pricing.id
  health_check {
    enabled             = true
    path                = "/actuator/health"
    protocol            = "HTTP"
    port                = "traffic-port"
    matcher             = "200"
    healthy_threshold   = 5
    unhealthy_threshold = 2
    interval            = 30
    timeout             = 5
  }
}
resource "aws_lb_target_group" "dashboard" {
  name        = "pricing-dashboard-tg"
  port        = 5173
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.pricing.id
  health_check {
    enabled             = true
    path                = "/"
    protocol            = "HTTP"
    port                = "traffic-port"
    matcher             = "200"
    healthy_threshold   = 5
    unhealthy_threshold = 2
    interval            = 30
    timeout             = 5
  }
}
resource "aws_lb_listener" "http" {
  count             = var.alb_enabled ? 1 : 0
  load_balancer_arn = aws_lb.pricing[0].arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dashboard.arn
    forward {
      target_group {
        arn    = aws_lb_target_group.dashboard.arn
        weight = 1
      }
    }
  }
}
resource "aws_lb_listener_rule" "api" {
  count        = var.alb_enabled ? 1 : 0
  listener_arn = aws_lb_listener.http[0].arn
  priority     = 2
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
  condition {
    path_pattern { values = ["/api/*"] }
  }
}
resource "aws_ecs_task_definition" "backend" {
  family                   = "pricing-backend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.execution.arn
  container_definitions = jsonencode([{
    name           = "Main"
    image          = format("%s:latest", aws_ecr_repository.backend.repository_url)
    cpu            = 0
    essential      = true
    mountPoints    = []
    volumesFrom    = []
    systemControls = []
    portMappings = [{
      containerPort = 8080
      hostPort      = 8080
      protocol      = "tcp"
      name          = "main-8080-tcp"
    }]
    environment = [
      { name = "SPRING_DATASOURCE_USERNAME", value = aws_db_instance.pricing.username },
      { name = "SPRING_DATASOURCE_URL", value = format("jdbc:postgresql://%s:%s/%s", aws_db_instance.pricing.address, aws_db_instance.pricing.port, aws_db_instance.pricing.db_name) }
    ]
    secrets = [{
      name      = "SPRING_DATASOURCE_PASSWORD"
      valueFrom = format("%s:password::", aws_secretsmanager_secret.rds_password.arn)
    }]
    healthCheck = {
      command     = ["CMD", "curl", "--fail", "--silent", "http://localhost:8080/actuator/health"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
    logConfiguration = {
      logDriver     = "awslogs"
      secretOptions = []
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.pricing.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "backend"
        "awslogs-create-group"  = "true"
      }
    }
  }])
}
resource "aws_ecs_task_definition" "dashboard" {
  family                   = "pricing-dashboard"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.execution.arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
  container_definitions = jsonencode([{
    name           = "Main"
    image          = format("%s:latest", aws_ecr_repository.dashboard.repository_url)
    cpu            = 0
    essential      = true
    mountPoints    = []
    volumesFrom    = []
    systemControls = []
    environment    = []
    portMappings = [{
      containerPort = 5173
      hostPort      = 5173
      protocol      = "tcp"
      name          = "main-5173-tcp"
      appProtocol   = "http"
    }]
    logConfiguration = {
      logDriver     = "awslogs"
      secretOptions = []
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.pricing.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "dashboard"
        "awslogs-create-group"  = "true"
      }
    }
  }])
}
resource "aws_ecs_service" "backend" {
  name                               = "pricing-backend-service"
  cluster                            = aws_ecs_cluster.pricing.id
  task_definition                    = aws_ecs_task_definition.backend.arn
  desired_count                      = var.backend_desired_count
  platform_version                   = "1.4.0"
  health_check_grace_period_seconds  = 300
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  enable_ecs_managed_tags            = true
  enable_execute_command             = false
  propagate_tags                     = "NONE"
  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 0
  }
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  network_configuration {
    subnets          = [aws_subnet.public["a"].id]
    security_groups  = [aws_security_group.backend.id]
    assign_public_ip = true
  }
  dynamic "load_balancer" {
    for_each = var.alb_enabled ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.backend.arn
      container_name   = "Main"
      container_port   = 8080
    }
  }
  depends_on = [aws_lb_listener_rule.api, aws_iam_role_policy.execution_secret]
}
resource "aws_ecs_service" "dashboard" {
  name                               = "pricing-dashboard-service"
  cluster                            = aws_ecs_cluster.pricing.id
  task_definition                    = aws_ecs_task_definition.dashboard.arn
  desired_count                      = var.dashboard_desired_count
  launch_type                        = "FARGATE"
  platform_version                   = "1.4.0"
  health_check_grace_period_seconds  = 0
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  enable_ecs_managed_tags            = true
  enable_execute_command             = false
  propagate_tags                     = "NONE"
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  network_configuration {
    subnets          = [aws_subnet.public["a"].id]
    security_groups  = [aws_security_group.dashboard.id]
    assign_public_ip = true
  }
  dynamic "load_balancer" {
    for_each = var.alb_enabled ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.dashboard.arn
      container_name   = "Main"
      container_port   = 5173
    }
  }
  depends_on = [aws_lb_listener.http, aws_iam_role_policy_attachment.execution_base]
}
output "alb_dns_name" {
  value = var.alb_enabled ? aws_lb.pricing[0].dns_name : null
}

resource "aws_security_group" "mock_server" {
  name        = "pricing-app-mock-server-sg"
  description = "Security group for Pricing App Mock Processor ECS tasks"
  vpc_id      = aws_vpc.pricing.id
  ingress {
    from_port       = 8081
    to_port         = 8081
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_security_group" "database_init" {
  name        = "pricing-app-database-init-sg"
  description = "Security group for the database initialization task"
  vpc_id      = aws_vpc.pricing.id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_secretsmanager_secret" "account_password" {
  name                    = "pricing-app/account-password"
  recovery_window_in_days = 0
}
resource "aws_secretsmanager_secret_version" "account_password" {
  count         = 1
  secret_id     = aws_secretsmanager_secret.account_password.id
  secret_string = jsonencode({ password = var.account_password })
  lifecycle {
    ignore_changes = [secret_string]
  }
}
resource "aws_ecr_repository" "mock_server" {
  name                 = "pricing-mock-server"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_scanning_configuration { scan_on_push = false }
  encryption_configuration { encryption_type = "AES256" }
}
resource "aws_ecs_task_definition" "database_init" {
  family                   = "pricing-database-init"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.execution.arn
  container_definitions = jsonencode([{
    name       = "DatabaseInit"
    image      = "postgres:16"
    essential  = true
    entryPoint = ["/bin/bash", "-c"]
    command    = [file("${path.module}/../local/init-db.sh")]
    environment = [
      { name = "PGHOST", value = aws_db_instance.pricing.address },
      { name = "PGPORT", value = tostring(aws_db_instance.pricing.port) },
      { name = "PGSSLMODE", value = "require" },
      { name = "POSTGRES_USER", value = aws_db_instance.pricing.username },
      { name = "POSTGRES_DB", value = aws_db_instance.pricing.db_name }
    ]
    secrets = [
      {
        name      = "PGPASSWORD"
        valueFrom = format("%s:password::", aws_secretsmanager_secret.rds_password.arn)
      },
      {
        name      = "ACCOUNT_PASSWORD"
        valueFrom = format("%s:password::", aws_secretsmanager_secret.account_password.arn)
      }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.pricing.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "database-init"
      }
    }
  }])
  depends_on = [
    aws_iam_role_policy.execution_secret,
    aws_iam_role_policy_attachment.execution_base,
    aws_secretsmanager_secret_version.account_password,
    aws_route_table_association.public
  ]
}
resource "aws_lb_target_group" "mock_server" {
  name        = "pricing-mock-server-tg"
  port        = 8081
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.pricing.id
  health_check {
    enabled             = true
    path                = "/actuator/health"
    protocol            = "HTTP"
    port                = "traffic-port"
    matcher             = "200"
    healthy_threshold   = 5
    unhealthy_threshold = 2
    interval            = 30
    timeout             = 5
  }
}
resource "aws_lb_listener_rule" "mock_server" {
  count        = var.alb_enabled ? 1 : 0
  listener_arn = aws_lb_listener.http[0].arn
  priority     = 1
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mock_server.arn
  }
  condition {
    path_pattern { values = ["/api/v1/mock/*"] }
  }
  depends_on = [aws_lb_listener_rule.api]
}
resource "aws_ecs_task_definition" "mock_server" {
  family                   = "pricing-mock-server"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.execution.arn
  container_definitions = jsonencode([{
    name      = "Main"
    image     = format("%s:latest", aws_ecr_repository.mock_server.repository_url)
    essential = true
    portMappings = [{
      containerPort = 8081
      hostPort      = 8081
      protocol      = "tcp"
      name          = "main-8081-tcp"
    }]
    environment = [
      { name = "SPRING_DATASOURCE_USERNAME", value = "accountuser" },
      {
        name = "SPRING_DATASOURCE_URL"
        value = format(
          "jdbc:postgresql://%s:%s/accountdb",
          aws_db_instance.pricing.address, aws_db_instance.pricing.port
        )
      }
    ]
    secrets = [{
      name      = "SPRING_DATASOURCE_PASSWORD"
      valueFrom = format("%s:password::", aws_secretsmanager_secret.account_password.arn)
    }]
    healthCheck = {
      command     = ["CMD", "curl", "--fail", "--silent", "http://localhost:8081/actuator/health"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
    logConfiguration = {
      logDriver     = "awslogs"
      secretOptions = []
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.pricing.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "mock-server"
        "awslogs-create-group"  = "true"
      }
    }
  }])
}
resource "aws_ecs_service" "mock_server" {
  name                               = "pricing-mock-server-service"
  cluster                            = aws_ecs_cluster.pricing.id
  task_definition                    = aws_ecs_task_definition.mock_server.arn
  desired_count                      = var.mock_server_desired_count
  launch_type                        = "FARGATE"
  platform_version                   = "1.4.0"
  health_check_grace_period_seconds  = 300
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  enable_ecs_managed_tags            = true
  enable_execute_command             = false
  propagate_tags                     = "NONE"
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  network_configuration {
    subnets          = [aws_subnet.public["a"].id]
    security_groups  = [aws_security_group.mock_server.id]
    assign_public_ip = true
  }
  dynamic "load_balancer" {
    for_each = var.alb_enabled ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.mock_server.arn
      container_name   = "Main"
      container_port   = 8081
    }
  }
  depends_on = [
    aws_lb_listener_rule.mock_server,
    aws_iam_role_policy.execution_secret,
    aws_iam_role_policy_attachment.execution_base
  ]
}
output "database_init" {
  value = {
    task_definition = aws_ecs_task_definition.database_init.arn
    subnet          = aws_subnet.public["a"].id
    security_group  = aws_security_group.database_init.id
  }
}
