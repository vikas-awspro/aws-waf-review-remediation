################################################################################
# Production environment — wires the 13 remediation modules together.
# Each module's tags carry the WAF Finding ID it remediates so cost reports
# and resource tags map back to the review.
################################################################################

data "aws_caller_identity" "current" {}

locals {
  common_tags = {
    Project = "plm-waf-remediation"
    Region  = var.region
  }
}

############################
# SNS topic for alerts (referenced by every module's alarms)
############################

resource "aws_kms_key" "alerts" {
  description             = "SNS alerts KMS key"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = local.common_tags
}

resource "aws_sns_topic" "alerts" {
  name              = "plm-platform-alerts"
  kms_master_key_id = aws_kms_key.alerts.arn
  tags              = local.common_tags
}

resource "aws_sns_topic_subscription" "pagerduty" {
  count                  = var.pagerduty_endpoint == "" ? 0 : 1
  topic_arn              = aws_sns_topic.alerts.arn
  protocol               = "https"
  endpoint               = var.pagerduty_endpoint
  endpoint_auto_confirms = true
}

resource "aws_sns_topic_subscription" "email" {
  for_each  = toset(var.email_subscribers)
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

############################
# Enhanced monitoring role (used by RDS)
############################

data "aws_iam_policy_document" "rds_monitoring_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rds_monitoring" {
  name               = "rds-enhanced-monitoring-plm"
  assume_role_policy = data.aws_iam_policy_document.rds_monitoring_assume.json
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

############################
# Backup IAM role (referenced by S3 bucket policy)
############################

data "aws_iam_policy_document" "backup_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backup" {
  name               = "plm-backup-role"
  assume_role_policy = data.aws_iam_policy_document.backup_assume.json
  tags               = local.common_tags
}

############################
# RDS SQL Server (SEC-02 + REL-01 + PERF-01 + COST-02 + PERF-07)
############################

module "rds" {
  source = "../../modules/rds-mssql"

  environment                  = "prod"
  isolated_subnet_ids          = var.isolated_subnet_ids
  security_group_ids           = var.rds_security_group_ids
  enhanced_monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  tags = local.common_tags
}

############################
# IAM app tier (SEC-01)
############################

module "iam_app_tier" {
  source = "../../modules/iam-app-tier"

  environment              = "prod"
  region                   = var.region
  account_id               = data.aws_caller_identity.current.account_id
  document_vault_bucket_arn = module.s3_vault.bucket_arn
  rds_resource_id          = var.rds_resource_id
  kms_key_arns             = [module.rds.kms_key_arn, aws_kms_key.alerts.arn]

  tags = local.common_tags
}

############################
# S3 document vault (SEC-03 + REL-06 + COST-03)
############################

module "s3_vault" {
  source = "../../modules/s3-document-vault"

  bucket_name        = "plm-app-documents-${data.aws_caller_identity.current.account_id}"
  kms_key_arn        = module.rds.kms_key_arn
  app_tier_role_arn  = module.iam_app_tier.role_arn
  backup_role_arn    = aws_iam_role.backup.arn
  replication_destination_arn     = var.replication_destination_arn
  replication_destination_kms_arn = var.replication_destination_kms_arn
  access_log_bucket  = var.access_log_bucket

  tags = local.common_tags
}

############################
# ALB + ASG (REL-03 + PERF-03 + PERF-04 + COST-05)
############################

module "alb_asg" {
  source = "../../modules/alb-asg"

  environment        = "prod"
  vpc_id             = var.vpc_id
  public_subnet_ids  = var.public_subnet_ids
  private_subnet_ids = var.private_subnet_ids

  alb_sg_id = var.alb_sg_id
  web_sg_id = var.web_sg_id
  app_sg_id = var.app_sg_id

  certificate_arn           = var.certificate_arn
  access_log_bucket         = var.access_log_bucket
  app_instance_profile_name = module.iam_app_tier.instance_profile_name
  ebs_kms_key_arn           = module.rds.kms_key_arn   # share platform CMK

  web_ami_id = var.web_ami_id
  app_ami_id = var.app_ami_id

  tags = local.common_tags
}

############################
# WAF (SEC-04)
############################

module "waf" {
  source = "../../modules/waf"

  environment    = "prod"
  region         = var.region
  alb_arn        = module.alb_asg.alb_arn
  kms_key_arn    = aws_kms_key.alerts.arn
  alerts_sns_arn = aws_sns_topic.alerts.arn

  rule_action = var.enable_waf_block_mode ? "block" : "count"

  tags = local.common_tags
}

############################
# RDS Proxy (REL-04)
############################

module "rds_proxy" {
  source = "../../modules/rds-proxy"

  environment         = "prod"
  region              = var.region
  isolated_subnet_ids = var.isolated_subnet_ids
  security_group_ids  = var.rds_proxy_security_group_ids
  rds_instance_id     = module.rds.instance_id
  master_secret_arn   = module.rds.master_secret_arn
  kms_key_arn         = module.rds.kms_key_arn
  alerts_sns_arn      = aws_sns_topic.alerts.arn

  tags = local.common_tags
}

############################
# ElastiCache Redis (PERF-02)
############################

module "elasticache" {
  source = "../../modules/elasticache"

  environment        = "prod"
  subnet_ids         = var.isolated_subnet_ids
  security_group_ids = var.elasticache_security_group_ids
  kms_key_arn        = aws_kms_key.alerts.arn
  alerts_sns_arn     = aws_sns_topic.alerts.arn

  tags = local.common_tags
}

############################
# Lambda integration — DLQ + PERF-05 SSM params (REL-05, PERF-05)
############################

module "lambda_integration" {
  source = "../../modules/lambda-integration"

  environment    = "prod"
  region         = var.region
  kms_key_arn    = aws_kms_key.alerts.arn
  alerts_sns_arn = aws_sns_topic.alerts.arn

  tags = local.common_tags
}

############################
# SSM Patch Manager (SEC-05)
############################

module "patch_manager" {
  source      = "../../modules/ssm-patch-manager"
  environment = "prod"
  tags        = local.common_tags
}

############################
# CloudTrail → Splunk (SEC-06)
############################

module "cloudtrail_siem" {
  source = "../../modules/cloudtrail-siem"

  environment                 = "prod"
  region                      = var.region
  kms_key_arn                 = aws_kms_key.alerts.arn
  alerts_sns_arn              = aws_sns_topic.alerts.arn
  splunk_hec_secret_id        = var.splunk_hec_secret_id
  firehose_failure_bucket_arn = var.firehose_failure_bucket_arn

  tags = local.common_tags
}

############################
# VPC Endpoints (COST-04)
############################

module "vpc_endpoints" {
  source = "../../modules/vpc-endpoints"

  environment             = "prod"
  region                  = var.region
  vpc_id                  = var.vpc_id
  private_subnet_ids      = var.private_subnet_ids
  private_route_table_ids = var.private_route_table_ids
  client_sg_ids           = concat([var.web_sg_id, var.app_sg_id], var.lambda_sg_ids)

  tags = local.common_tags
}

############################
# DLM snapshot lifecycle (COST-06)
############################

module "dlm" {
  source = "../../modules/dlm-snapshots"

  environment    = "prod"
  alerts_sns_arn = aws_sns_topic.alerts.arn

  tags = local.common_tags
}

############################
# FIS Game Day (REL-07)
############################

resource "aws_cloudwatch_metric_alarm" "alb_5xx_kill_switch" {
  alarm_name          = "fis-kill-switch-alb-5xx"
  alarm_description   = "Stop FIS experiments if ALB 5xx spikes"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 50
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions = {
    LoadBalancer = split(":loadbalancer/", module.alb_asg.alb_arn)[1]
  }
  tags = local.common_tags
}

module "fis" {
  source = "../../modules/fis-gameday"

  environment        = "prod"
  rds_instance_arn   = "arn:aws:rds:${var.region}:${data.aws_caller_identity.current.account_id}:db:${module.rds.instance_id}"
  az_a_subnet_arns   = [for s in var.private_subnet_ids :
                        "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:subnet/${s}"]
  alb_5xx_alarm_arn  = aws_cloudwatch_metric_alarm.alb_5xx_kill_switch.arn

  tags = local.common_tags
}

############################
# Outputs
############################

output "alb_dns_name"            { value = module.alb_asg.alb_dns_name }
output "rds_endpoint"            { value = module.rds.endpoint }
output "rds_proxy_endpoint"      { value = module.rds_proxy.proxy_endpoint }
output "elasticache_endpoint"    { value = module.elasticache.primary_endpoint }
output "document_vault_bucket"   { value = module.s3_vault.bucket_name }
output "alerts_topic_arn"        { value = aws_sns_topic.alerts.arn }
output "waf_web_acl_arn"         { value = module.waf.web_acl_arn }
output "dlq_url"                 { value = module.lambda_integration.dlq_url }
output "fis_experiment_template_ids" { value = module.fis.experiment_template_ids }
