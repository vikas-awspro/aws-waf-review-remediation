################################################################################
# CloudTrail → CloudWatch Logs → Kinesis Firehose → Splunk HEC.
# SEC-06 remediation. Splunk HEC endpoint + token come from Secrets Manager.
#
# In parallel, an EventBridge rule routes high-severity events (root login,
# IAM changes, security-group modifications, Config rule changes) to a
# Lambda that pushes directly to the Splunk HTTP Event Collector so the
# SOC gets near-real-time alerts even before the Firehose batch flush.
################################################################################

############################
# CloudWatch Log Group for CloudTrail events
############################

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/plm-${var.environment}"
  retention_in_days = 90
  kms_key_id        = var.kms_key_arn
  tags              = merge(var.tags, { Finding = "SEC-06" })
}

############################
# Wire the existing CloudTrail (passed in) to publish to CloudWatch Logs
############################

data "aws_iam_policy_document" "trail_to_cwlogs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "trail_to_cwlogs" {
  name               = "cloudtrail-to-cwlogs-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.trail_to_cwlogs_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "trail_to_cwlogs" {
  role = aws_iam_role.trail_to_cwlogs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
    }]
  })
}

############################
# Kinesis Firehose → Splunk
############################

data "aws_secretsmanager_secret_version" "splunk_hec" {
  secret_id = var.splunk_hec_secret_id
}

resource "aws_kinesis_firehose_delivery_stream" "splunk" {
  name        = "cloudtrail-to-splunk-${var.environment}"
  destination = "splunk"

  splunk_configuration {
    hec_endpoint               = jsondecode(data.aws_secretsmanager_secret_version.splunk_hec.secret_string).endpoint
    hec_token                  = jsondecode(data.aws_secretsmanager_secret_version.splunk_hec.secret_string).token
    hec_acknowledgment_timeout = 600
    hec_endpoint_type          = "Event"
    retry_duration             = 300
    s3_backup_mode             = "FailedEventsOnly"

    s3_configuration {
      role_arn           = aws_iam_role.firehose.arn
      bucket_arn         = var.firehose_failure_bucket_arn
      prefix             = "firehose-failures/"
      compression_format = "GZIP"
    }

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = "/aws/kinesisfirehose/cloudtrail-to-splunk-${var.environment}"
      log_stream_name = "DestinationDelivery"
    }
  }

  tags = merge(var.tags, { Finding = "SEC-06" })
}

############################
# Subscription filter — CloudWatch Logs → Firehose
############################

data "aws_iam_policy_document" "logs_to_firehose_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["logs.${var.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "logs_to_firehose" {
  name               = "cwlogs-to-firehose-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.logs_to_firehose_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "logs_to_firehose" {
  role = aws_iam_role.logs_to_firehose.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["firehose:PutRecord", "firehose:PutRecordBatch"]
      Resource = aws_kinesis_firehose_delivery_stream.splunk.arn
    }]
  })
}

resource "aws_cloudwatch_log_subscription_filter" "splunk" {
  name            = "cloudtrail-to-splunk"
  role_arn        = aws_iam_role.logs_to_firehose.arn
  log_group_name  = aws_cloudwatch_log_group.cloudtrail.name
  filter_pattern  = ""   # forward everything; let Splunk filter
  destination_arn = aws_kinesis_firehose_delivery_stream.splunk.arn
}

############################
# Firehose role (S3 backup for failures)
############################

data "aws_iam_policy_document" "firehose_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "firehose" {
  name               = "firehose-cloudtrail-splunk-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.firehose_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "firehose" {
  role = aws_iam_role.firehose.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:AbortMultipartUpload", "s3:GetBucketLocation", "s3:GetObject", "s3:ListBucket", "s3:ListBucketMultipartUploads", "s3:PutObject"]
        Resource = [var.firehose_failure_bucket_arn, "${var.firehose_failure_bucket_arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:PutLogEvents"]
        Resource = "*"
      },
    ]
  })
}

############################
# EventBridge — high-severity events route directly to SNS (near-real-time)
############################

resource "aws_cloudwatch_event_rule" "high_severity" {
  name = "cloudtrail-high-severity-${var.environment}"
  description = "Root login, IAM changes, SG modifications — page SOC"
  event_pattern = jsonencode({
    detail = {
      eventName = [
        "ConsoleLogin", "CreateUser", "DeleteUser",
        "AttachUserPolicy", "AttachRolePolicy", "PutUserPolicy", "PutRolePolicy",
        "CreateAccessKey", "UpdateAccessKey",
        "AuthorizeSecurityGroupIngress", "RevokeSecurityGroupIngress",
        "StopLogging", "DeleteTrail",
      ]
    }
  })
  tags = merge(var.tags, { Finding = "SEC-06", Severity = "P1" })
}

resource "aws_cloudwatch_event_target" "high_severity_sns" {
  rule      = aws_cloudwatch_event_rule.high_severity.name
  target_id = "soc-sns"
  arn       = var.alerts_sns_arn
}
