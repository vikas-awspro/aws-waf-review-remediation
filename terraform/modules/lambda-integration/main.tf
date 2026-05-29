################################################################################
# Lambda integration layer — REL-05 (DLQ + alarm) + PERF-05 (presigned URL expiry).
# Provisions the DLQ + CloudWatch alarm + IAM permissions required to attach
# to every integration Lambda. The Lambda code itself lives in services/
# and is deployed via the platform's CI/CD pipeline.
################################################################################

############################
# REL-05 — Dead-letter queue
############################

resource "aws_sqs_queue" "dlq" {
  name                       = "app-integration-dlq-${var.environment}"
  message_retention_seconds  = 1209600   # 14 days
  visibility_timeout_seconds = 300
  kms_master_key_id          = var.kms_key_arn
  tags                       = merge(var.tags, { Finding = "REL-05" })
}

############################
# Alarm — DLQ has messages
############################

resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  alarm_name          = "app-integration-dlq-messages-${var.environment}"
  alarm_description   = "Integration Lambda DLQ has messages — investigate failed events"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions          = { QueueName = aws_sqs_queue.dlq.name }
  alarm_actions       = [var.alerts_sns_arn]
  tags                = merge(var.tags, { Finding = "REL-05", Severity = "P2" })
}

############################
# IAM policy fragment for Lambda execution roles to send to DLQ
############################

data "aws_iam_policy_document" "dlq_send" {
  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.dlq.arn]
  }
  statement {
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [var.kms_key_arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["sqs.${var.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "dlq_send" {
  name        = "app-integration-dlq-send-${var.environment}"
  description = "Attach to integration Lambda execution roles to enable DLQ delivery"
  policy      = data.aws_iam_policy_document.dlq_send.json
  tags        = var.tags
}

############################
# Reprocessing Lambda — drains the DLQ on operator trigger
############################

data "aws_iam_policy_document" "reprocess_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "reprocess" {
  name               = "dlq-reprocess-reprocess-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.reprocess_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "reprocess" {
  role = aws_iam_role.reprocess.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility",
        ]
        Resource = aws_sqs_queue.dlq.arn
      },
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = "arn:aws:lambda:*:*:function:app-integration-*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      },
    ]
  })
}

############################
# PERF-05 — presigned URL settings stored in SSM Parameter Store so the
# upload Lambda can read them without a redeploy when the value is tuned.
############################

resource "aws_ssm_parameter" "presigned_url_expiry_seconds" {
  name        = "/app/upload/presigned-url-expiry-seconds"
  type        = "String"
  value       = "3600"   # PERF-05 — was 300
  description = "Presigned URL expiry — 1 hour for large CAD upload support"
  tags        = merge(var.tags, { Finding = "PERF-05" })
}

resource "aws_ssm_parameter" "multipart_threshold_bytes" {
  name        = "/app/upload/multipart-threshold-bytes"
  type        = "String"
  value       = "104857600"   # 100 MB — switch to multipart above this
  description = "Files larger than this use S3 multipart upload (PERF-05)"
  tags        = merge(var.tags, { Finding = "PERF-05" })
}
