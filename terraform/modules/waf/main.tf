################################################################################
# AWS WAF v2 Web ACL — SEC-04 — associated with the internet-facing ALB.
#
# Rule groups deploy in COUNT mode by default (var.rule_action = "count") for
# the first 2 weeks. Operator flips var.rule_action = "block" after baselining
# WAF logs to ensure no false positives against legitimate application traffic.
################################################################################

resource "aws_wafv2_web_acl" "this" {
  name        = "plm-app-${var.environment}"
  description = "PLM application web ACL — OWASP, SQLi, Windows/IIS, bad-input filters"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # 1. Core OWASP rule set
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10

    override_action {
      dynamic "none"  { for_each = var.rule_action == "block" ? [1] : [] content {} }
      dynamic "count" { for_each = var.rule_action == "count" ? [1] : [] content {} }
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "common-rule-set"
      sampled_requests_enabled   = true
    }
  }

  # 2. SQL injection
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 20

    override_action {
      dynamic "none"  { for_each = var.rule_action == "block" ? [1] : [] content {} }
      dynamic "count" { for_each = var.rule_action == "count" ? [1] : [] content {} }
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesSQLiRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "sqli-rule-set"
      sampled_requests_enabled   = true
    }
  }

  # 3. Windows / IIS specific exploits — app runs on Windows Server + IIS
  rule {
    name     = "AWSManagedRulesWindowsRuleSet"
    priority = 30

    override_action {
      dynamic "none"  { for_each = var.rule_action == "block" ? [1] : [] content {} }
      dynamic "count" { for_each = var.rule_action == "count" ? [1] : [] content {} }
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesWindowsRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "windows-rule-set"
      sampled_requests_enabled   = true
    }
  }

  # 4. Known bad inputs (CVE patterns, exploitation payloads)
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 40

    override_action {
      dynamic "none"  { for_each = var.rule_action == "block" ? [1] : [] content {} }
      dynamic "count" { for_each = var.rule_action == "count" ? [1] : [] content {} }
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "plm-app-acl"
    sampled_requests_enabled   = true
  }

  tags = merge(var.tags, { Finding = "SEC-04" })
}

############################
# Logging to CloudWatch Logs + S3 (centralised security log bucket)
############################

resource "aws_cloudwatch_log_group" "waf" {
  name              = "aws-waf-logs-plm-${var.environment}"   # must start with 'aws-waf-logs-'
  retention_in_days = 90
  kms_key_id        = var.kms_key_arn
  tags              = var.tags
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]
  resource_arn            = aws_wafv2_web_acl.this.arn

  redacted_fields {
    single_header { name = "authorization" }
  }
  redacted_fields {
    single_header { name = "cookie" }
  }
}

############################
# Association with ALB
############################

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = var.alb_arn
  web_acl_arn  = aws_wafv2_web_acl.this.arn
}

############################
# Alarm — BlockedRequests > 100 in 5 min (potential attack)
############################

resource "aws_cloudwatch_metric_alarm" "blocked_spike" {
  alarm_name          = "waf-plm-blocked-requests-spike-${var.environment}"
  alarm_description   = "WAF blocked requests > 100 in 5 min — investigate"
  namespace           = "AWS/WAFV2"
  metric_name         = "BlockedRequests"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 100
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions = {
    WebACL = aws_wafv2_web_acl.this.name
    Region = var.region
    Rule   = "ALL"
  }
  alarm_actions = [var.alerts_sns_arn]
  tags          = merge(var.tags, { Finding = "SEC-04", Severity = "P2" })
}
