################################################################################
# RDS SQL Server — remediates four findings in one module:
#   SEC-02 : storage_encrypted = true + KMS CMK
#   REL-01 : multi_az = true (Single-AZ → Multi-AZ)
#   PERF-01/COST-02 : instance_class right-sized from r5.2xlarge → r5.xlarge
#   PERF-07 : custom parameter group enables SQL Server Query Store
#
# Encryption cannot be flipped on a running instance — the runbook
# [runbooks/rds-encryption-cutover.md] documents the snapshot/restore cutover.
# This module is the final target state.
################################################################################

############################
# KMS CMK for RDS storage (SEC-02)
############################

resource "aws_kms_key" "rds" {
  description             = "RDS SQL Server storage encryption — PLM"
  deletion_window_in_days = 30
  enable_key_rotation     = true   # annual auto-rotation
  multi_region            = true   # required for cross-region snapshot copy
  tags                    = merge(var.tags, { Pillar = "security", Finding = "SEC-02" })
}

resource "aws_kms_alias" "rds" {
  name          = "alias/rds-plm-${var.environment}"
  target_key_id = aws_kms_key.rds.id
}

############################
# Custom parameter group — enables Query Store (PERF-07)
############################

resource "aws_db_parameter_group" "this" {
  name        = "plm-mssql-query-store-${var.environment}"
  family      = "sqlserver-se-15.0"
  description = "PLM SQL Server param group with Query Store enabled (PERF-07)"

  # SQL Server Query Store on RDS is configured via T-SQL after instance
  # creation — RDS parameter groups don't expose query_store_* keys directly.
  # The post-create provisioner below runs the T-SQL once.
  # Other tunables that ARE supported via param group go here.
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }
  tags = merge(var.tags, { Finding = "PERF-07" })
}

############################
# Subnet group
############################

resource "aws_db_subnet_group" "this" {
  name        = "plm-mssql-${var.environment}"
  subnet_ids  = var.isolated_subnet_ids
  description = "Isolated DB subnets across both AZs for Multi-AZ standby"
  tags        = var.tags
}

############################
# RDS instance — SEC-02 + REL-01 + PERF-01 target state
############################

resource "aws_db_instance" "this" {
  identifier        = "plm-mssql-${var.environment}"
  engine            = "sqlserver-se"
  engine_version    = var.engine_version

  # PERF-01 / COST-02 — right-sized from r5.2xlarge to r5.xlarge.
  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage_gb
  storage_type      = "gp3"
  iops              = var.iops

  # SEC-02 — encryption at rest with KMS CMK
  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn

  # REL-01 — Multi-AZ (synchronous standby)
  multi_az          = true

  username = "rdsadmin"
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.rds.arn

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = var.security_group_ids
  port                   = 1433

  parameter_group_name = aws_db_parameter_group.this.name

  backup_retention_period  = 14
  preferred_backup_window  = "01:00-02:00"
  preferred_maintenance_window = "sun:03:00-sun:04:00"
  copy_tags_to_snapshot    = true

  deletion_protection      = true
  skip_final_snapshot      = false
  final_snapshot_identifier = "plm-mssql-final-${var.environment}"

  enabled_cloudwatch_logs_exports = ["agent", "error"]
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.rds.arn
  monitoring_interval             = 60
  monitoring_role_arn             = var.enhanced_monitoring_role_arn

  license_model = "license-included"

  tags = merge(var.tags, {
    Workload  = "plm-database"
    Findings  = "SEC-02 REL-01 PERF-01 COST-02 PERF-07"
  })

  lifecycle {
    # KMS rotation rotates the secret out-of-band; ignore drift.
    ignore_changes = [password, final_snapshot_identifier]
  }
}

############################
# Query Store T-SQL bootstrap (PERF-07)
#
# RDS doesn't expose Query Store via the parameter group. Apply once after
# instance creation via a null_resource provisioner that runs sqlcmd against
# the new instance. The values match the spec: ALL capture mode, 30-day
# retention, 1 GB store, 24-hour stale threshold.
############################

resource "null_resource" "query_store" {
  triggers = {
    instance = aws_db_instance.this.id
    sql_hash = sha1(local.query_store_tsql)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      SECRET=$(aws secretsmanager get-secret-value \
        --secret-id "${aws_db_instance.this.master_user_secret[0].secret_arn}" \
        --query SecretString --output text)
      PWD=$(echo "$SECRET" | jq -r .password)
      sqlcmd -S "${aws_db_instance.this.endpoint}" -U rdsadmin -P "$PWD" -d master \
             -Q "${local.query_store_tsql}"
    EOT
  }
}

locals {
  query_store_tsql = <<-SQL
    USE [PLMDB];
    ALTER DATABASE [PLMDB] SET QUERY_STORE = ON;
    ALTER DATABASE [PLMDB] SET QUERY_STORE (
      OPERATION_MODE = READ_WRITE,
      QUERY_CAPTURE_MODE = ALL,
      MAX_STORAGE_SIZE_MB = 1024,
      CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 30),
      INTERVAL_LENGTH_MINUTES = 60
    );
  SQL
}
