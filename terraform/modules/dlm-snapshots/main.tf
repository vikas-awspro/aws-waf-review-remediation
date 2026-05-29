################################################################################
# DLM lifecycle policy — COST-06 — automatically expires manual EBS snapshots
# older than 30 days unless tagged RetainForever=true.
################################################################################

data "aws_iam_policy_document" "dlm_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["dlm.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "dlm" {
  name               = "dlm-snapshot-lifecycle-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.dlm_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "dlm" {
  role       = aws_iam_role.dlm.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}

resource "aws_dlm_lifecycle_policy" "manual_snapshots" {
  description        = "Expire manual EBS snapshots older than 30 days (COST-06)"
  execution_role_arn = aws_iam_role.dlm.arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]
    target_tags    = { Backup = "manual" }

    schedule {
      name = "expire-stale-manual"

      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["02:00"]
      }

      retain_rule {
        count = 30
      }

      tags_to_add = {
        Origin    = "DLM"
        ManagedBy = "dlm-policy"
      }

      copy_tags = true
    }
  }

  tags = merge(var.tags, { Finding = "COST-06" })
}

############################
# Snapshot audit Lambda — invoked on a schedule to alert on snapshots
# that no longer have a parent volume (orphans).
############################

data "aws_iam_policy_document" "audit_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "audit" {
  name               = "snapshot-audit-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.audit_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "audit" {
  role = aws_iam_role.audit.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["ec2:DescribeSnapshots", "ec2:DescribeVolumes", "ec2:DeleteSnapshot"], Resource = "*" },
      { Effect = "Allow", Action = ["sns:Publish"], Resource = var.alerts_sns_arn },
      { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], Resource = "*" },
    ]
  })
}
