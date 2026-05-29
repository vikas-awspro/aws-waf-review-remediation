variable "region"          { type = string  default = "eu-west-1" }
variable "replica_region"  { type = string  default = "eu-central-1" }

# Network — references existing VPC from the original ARAS migration project.
variable "vpc_id"                       { type = string }
variable "private_subnet_ids"           { type = list(string) }
variable "private_route_table_ids"      { type = list(string) }
variable "isolated_subnet_ids"          { type = list(string) }
variable "public_subnet_ids"            { type = list(string) }
variable "rds_security_group_ids"       { type = list(string) }
variable "rds_proxy_security_group_ids" { type = list(string) }
variable "elasticache_security_group_ids" { type = list(string) }
variable "alb_sg_id"                    { type = string }
variable "web_sg_id"                    { type = string }
variable "app_sg_id"                    { type = string }
variable "lambda_sg_ids"                { type = list(string)  default = [] }

variable "rds_resource_id" {
  description = "Stable RDS resource ID — used in the IAM rds-db:connect resource ARN"
  type        = string
}

variable "certificate_arn"   { type = string }
variable "web_ami_id"        { type = string }
variable "app_ami_id"        { type = string }
variable "access_log_bucket" { type = string }
variable "firehose_failure_bucket_arn" { type = string }
variable "replication_destination_arn" { type = string }
variable "replication_destination_kms_arn" { type = string }

variable "splunk_hec_secret_id" { type = string  default = "soc/splunk/hec" }

variable "email_subscribers"  { type = list(string)  default = [] }
variable "pagerduty_endpoint" { type = string  default = ""  sensitive = true }

variable "enable_waf_block_mode" {
  description = "Flip to true after 2-week COUNT mode baseline (SEC-04)"
  type        = bool
  default     = false
}
