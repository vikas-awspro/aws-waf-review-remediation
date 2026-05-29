################################################################################
# ElastiCache Redis — PERF-02 — cache layer for the application reference data.
# Multi-AZ replication group; the integration Lambda layer reads from
# this cache with a 15-minute TTL and cache-aside semantics.
################################################################################

resource "aws_elasticache_subnet_group" "this" {
  name       = "app-cache-${var.environment}"
  subnet_ids = var.subnet_ids
  tags       = var.tags
}

resource "aws_elasticache_parameter_group" "this" {
  name        = "app-cache-${var.environment}"
  family      = "redis7"
  description = "the application reference data cache — PERF-02"

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }
  tags = merge(var.tags, { Finding = "PERF-02" })
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id       = "app-cache-${var.environment}"
  description                = "the application reference data cache"
  engine                     = "redis"
  engine_version             = "7.1"
  node_type                  = "cache.r6g.large"
  port                       = 6379
  parameter_group_name       = aws_elasticache_parameter_group.this.name
  subnet_group_name          = aws_elasticache_subnet_group.this.name
  security_group_ids         = var.security_group_ids

  num_cache_clusters         = 2     # primary + 1 replica = Multi-AZ failover
  automatic_failover_enabled = true
  multi_az_enabled           = true

  at_rest_encryption_enabled = true
  kms_key_id                 = var.kms_key_arn
  transit_encryption_enabled = true

  snapshot_retention_limit   = 7
  snapshot_window            = "01:00-02:00"

  log_delivery_configuration {
    destination_type = "cloudwatch-logs"
    destination      = aws_cloudwatch_log_group.slow.name
    log_format       = "json"
    log_type         = "slow-log"
  }

  tags = merge(var.tags, { Finding = "PERF-02" })
}

resource "aws_cloudwatch_log_group" "slow" {
  name              = "/aws/elasticache/app-cache-${var.environment}/slow"
  retention_in_days = 30
  kms_key_id        = var.kms_key_arn
  tags              = var.tags
}

############################
# Alarm — cache miss rate > 50% over 15 min (indicates cache key churn)
############################

resource "aws_cloudwatch_metric_alarm" "cache_miss_rate" {
  alarm_name          = "elasticache-app-cache-miss-high-${var.environment}"
  alarm_description   = "Cache miss rate > 50% — investigate TTL or key cardinality"
  namespace           = "AWS/ElastiCache"
  metric_name         = "CacheMissRate"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 0.50
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions          = { CacheClusterId = "app-cache-${var.environment}-001" }
  alarm_actions       = [var.alerts_sns_arn]
  tags                = merge(var.tags, { Finding = "PERF-02", Severity = "P3" })
}
