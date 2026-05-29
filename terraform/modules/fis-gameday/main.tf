################################################################################
# AWS Fault Injection Simulator (FIS) — REL-07 — four experiment templates
# corresponding to the Game Day scenarios in runbooks/game-day.md:
#   1. EC2 instance termination (ASG replacement test)
#   2. RDS failover (Multi-AZ failover behaviour)
#   3. AZ network partition (cross-AZ resilience)
#   4. Excess Lambda errors (DLQ behaviour)
################################################################################

data "aws_iam_policy_document" "fis_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["fis.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "fis" {
  name               = "fis-experiment-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.fis_assume.json
  tags               = merge(var.tags, { Finding = "REL-07" })
}

resource "aws_iam_role_policy_attachment" "fis" {
  for_each = toset([
    "arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorEC2Access",
    "arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorRDSAccess",
    "arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorNetworkAccess",
  ])
  role       = aws_iam_role.fis.name
  policy_arn = each.value
}

############################
# Experiment templates
############################

# 1. Terminate one web-tier EC2
resource "aws_fis_experiment_template" "terminate_ec2" {
  description = "Terminate one web-tier EC2; expect ASG replacement within 5 minutes"
  role_arn    = aws_iam_role.fis.arn

  action {
    name      = "terminate-instance"
    action_id = "aws:ec2:terminate-instances"
    target {
      key   = "Instances"
      value = "web-tier-target"
    }
  }

  target {
    name           = "web-tier-target"
    resource_type  = "aws:ec2:instance"
    selection_mode = "COUNT(1)"
    resource_tag {
      key   = "Tier"
      value = "web"
    }
  }

  stop_condition { source = "none" }

  tags = merge(var.tags, { Finding = "REL-07", Scenario = "ec2-termination" })
}

# 2. RDS failover — validates Multi-AZ + RDS Proxy reconnection
resource "aws_fis_experiment_template" "rds_failover" {
  description = "Force RDS Multi-AZ failover; ARAS should reconnect via RDS Proxy in < 60s"
  role_arn    = aws_iam_role.fis.arn

  action {
    name      = "reboot-with-failover"
    action_id = "aws:rds:reboot-db-instances"
    parameter {
      key   = "forceFailover"
      value = "true"
    }
    target {
      key   = "DBInstances"
      value = "rds-target"
    }
  }

  target {
    name          = "rds-target"
    resource_type = "aws:rds:db"
    resource_arns = [var.rds_instance_arn]
    selection_mode = "ALL"
  }

  stop_condition { source = "none" }

  tags = merge(var.tags, { Finding = "REL-07", Scenario = "rds-failover" })
}

# 3. AZ network partition — block all traffic to instances in one AZ
resource "aws_fis_experiment_template" "az_partition" {
  description = "Network-disrupt subnet AZ-a — validate cross-AZ resilience"
  role_arn    = aws_iam_role.fis.arn

  action {
    name      = "disrupt-connectivity"
    action_id = "aws:network:disrupt-connectivity"
    parameter {
      key   = "duration"
      value = "PT5M"
    }
    parameter {
      key   = "scope"
      value = "availability-zone"
    }
    target {
      key   = "Subnets"
      value = "az-a-subnets"
    }
  }

  target {
    name          = "az-a-subnets"
    resource_type = "aws:ec2:subnet"
    resource_arns = var.az_a_subnet_arns
    selection_mode = "ALL"
  }

  stop_condition {
    source = "aws:cloudwatch:alarm"
    value  = var.alb_5xx_alarm_arn
  }

  tags = merge(var.tags, { Finding = "REL-07", Scenario = "az-partition" })
}
