################################################################################
# SSM Patch Manager — SEC-05 — enrols EC2 instances + creates patch baseline,
# maintenance window, and association so Critical + Security patches apply
# automatically every Sunday 01:00–03:00 GMT with a 7-day approval delay.
#
# Instance IAM role: AmazonSSMManagedInstanceCore is attached by the
# iam-app-tier module — no separate role here.
################################################################################

resource "aws_ssm_patch_baseline" "windows" {
  name             = "plm-app-windows-${var.environment}"
  description      = "Windows Server baseline — Critical + Security, 7-day approval delay"
  operating_system = "WINDOWS"

  approval_rule {
    approve_after_days = 7
    compliance_level   = "CRITICAL"
    patch_filter {
      key    = "CLASSIFICATION"
      values = ["CriticalUpdates", "SecurityUpdates"]
    }
    patch_filter {
      key    = "MSRC_SEVERITY"
      values = ["Critical", "Important"]
    }
  }

  tags = merge(var.tags, { Finding = "SEC-05" })
}

resource "aws_ssm_maintenance_window" "patching" {
  name              = "plm-app-patching-${var.environment}"
  description       = "Weekly patching — Sun 01:00–03:00 GMT (SEC-05)"
  schedule          = "cron(0 1 ? * SUN *)"
  schedule_timezone = "Etc/GMT"
  duration          = 2
  cutoff            = 1
  tags              = var.tags
}

resource "aws_ssm_maintenance_window_target" "instances" {
  window_id     = aws_ssm_maintenance_window.patching.id
  name          = "plm-instances"
  resource_type = "INSTANCE"

  targets {
    key    = "tag:Patch"
    values = ["true"]
  }
}

resource "aws_ssm_maintenance_window_task" "scan" {
  name             = "scan-instances"
  description      = "AWS-RunPatchBaseline (Scan) — runs before Install"
  window_id        = aws_ssm_maintenance_window.patching.id
  task_type        = "RUN_COMMAND"
  task_arn         = "AWS-RunPatchBaseline"
  priority         = 1
  service_role_arn = aws_iam_role.maintenance.arn
  max_concurrency  = "50%"
  max_errors       = "10%"

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.instances.id]
  }

  task_invocation_parameters {
    run_command_parameters {
      parameter {
        name   = "Operation"
        values = ["Scan"]
      }
      timeout_seconds = 600
    }
  }
}

resource "aws_ssm_maintenance_window_task" "install" {
  name             = "install-patches"
  description      = "AWS-RunPatchBaseline (Install)"
  window_id        = aws_ssm_maintenance_window.patching.id
  task_type        = "RUN_COMMAND"
  task_arn         = "AWS-RunPatchBaseline"
  priority         = 2
  service_role_arn = aws_iam_role.maintenance.arn
  max_concurrency  = "50%"
  max_errors       = "10%"

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.instances.id]
  }

  task_invocation_parameters {
    run_command_parameters {
      parameter {
        name   = "Operation"
        values = ["Install"]
      }
      parameter {
        name   = "RebootOption"
        values = ["RebootIfNeeded"]
      }
      timeout_seconds = 3600
    }
  }
}

resource "aws_ssm_patch_group" "this" {
  baseline_id = aws_ssm_patch_baseline.windows.id
  patch_group = "plm-app-${var.environment}"
}

############################
# Service role for maintenance window tasks
############################

data "aws_iam_policy_document" "maintenance_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ssm.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "maintenance" {
  name               = "ssm-maintenance-window-plm-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.maintenance_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "maintenance" {
  role       = aws_iam_role.maintenance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonSSMMaintenanceWindowRole"
}
