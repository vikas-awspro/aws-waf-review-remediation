variable "bucket_name"        { type = string }
variable "kms_key_arn"        { type = string }
variable "app_tier_role_arn"  { type = string }
variable "backup_role_arn"    { type = string }

variable "replication_destination_arn"      { type = string }
variable "replication_destination_kms_arn"  { type = string }

variable "access_log_bucket" {
  type    = string
  default = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
