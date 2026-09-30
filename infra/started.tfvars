# Started configuration. Terraform manages RDS state as well as the ALB and ECS services.
# The orchestrator must ensure RDS is available before scaling ECS up.
rds_state               = "available"
alb_enabled             = true
backend_desired_count   = 1
dashboard_desired_count = 1
