# Stopped configuration. Terraform keeps target groups and persistent infrastructure.
# The orchestrator must scale ECS down and confirm tasks stop before stopping RDS.
rds_state               = "stopped"
alb_enabled             = false
backend_desired_count   = 0
dashboard_desired_count = 0
