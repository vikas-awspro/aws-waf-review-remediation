variable "environment"        { type = string }
variable "region"             { type = string }
variable "isolated_subnet_ids" { type = list(string) }
variable "security_group_ids" { type = list(string) }
variable "rds_instance_id"    { type = string }
variable "master_secret_arn"  { type = string }
variable "kms_key_arn"        { type = string }
variable "alerts_sns_arn"     { type = string }

variable "tags" {
  type    = map(string)
  default = {}
}
