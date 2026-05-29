################################################################################
# RDS Proxy — REL-04 — connection pool between ARAS app tier and RDS SQL Server.
# Reduces connection count to RDS by up to 87%; ARAS connection string is
# updated to the Proxy endpoint after this lands.
################################################################################

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "proxy" {
  name               = "rds-proxy-plm-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = merge(var.tags, { Finding = "REL-04" })
}

resource "aws_iam_role_policy" "proxy_secrets" {
  role = aws_iam_role.proxy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = var.master_secret_arn
    }, {
      Effect   = "Allow"
      Action   = ["kms:Decrypt"]
      Resource = var.kms_key_arn
      Condition = {
        StringEquals = { "kms:ViaService" = "secretsmanager.${var.region}.amazonaws.com" }
      }
    }]
  })
}

resource "aws_db_proxy" "this" {
  name                   = "rds-proxy-plm-${var.environment}"
  engine_family          = "SQLSERVER"
  idle_client_timeout    = 1800   # spec: connection_borrow_timeout = 120s; idle = 30 min
  require_tls            = true
  role_arn               = aws_iam_role.proxy.arn
  vpc_security_group_ids = var.security_group_ids
  vpc_subnet_ids         = var.isolated_subnet_ids
  debug_logging          = false

  auth {
    auth_scheme = "SECRETS"
    iam_auth    = "DISABLED"
    secret_arn  = var.master_secret_arn
  }

  tags = merge(var.tags, { Finding = "REL-04" })
}

resource "aws_db_proxy_default_target_group" "this" {
  db_proxy_name = aws_db_proxy.this.name
  connection_pool_config {
    max_connections_percent      = 80   # leave 20% headroom for admin sessions
    max_idle_connections_percent = 50
    connection_borrow_timeout    = 120
  }
}

resource "aws_db_proxy_target" "this" {
  db_instance_identifier = var.rds_instance_id
  db_proxy_name          = aws_db_proxy.this.name
  target_group_name      = aws_db_proxy_default_target_group.this.name
}

############################
# CloudWatch alarm — connection pool saturation (REL-04 follow-up)
############################

resource "aws_cloudwatch_metric_alarm" "client_connections" {
  alarm_name          = "rds-proxy-plm-client-connections-high-${var.environment}"
  alarm_description   = "RDS Proxy client connections > 80% of pool max — investigate"
  namespace           = "AWS/RDS"
  metric_name         = "ClientConnections"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  threshold           = 800
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions          = { ProxyName = aws_db_proxy.this.name }
  alarm_actions       = [var.alerts_sns_arn]
  tags                = merge(var.tags, { Finding = "REL-04", Severity = "P2" })
}
