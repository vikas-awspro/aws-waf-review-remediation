variable "environment"     { type = string }
variable "region"          { type = string }
variable "account_id"      { type = string }

variable "document_vault_bucket_arn" { type = string }
variable "rds_resource_id"           { type = string }
variable "kms_key_arns"              { type = list(string) }

variable "create_access_analyser" { type = bool  default = true }

variable "tags" {
  type    = map(string)
  default = {}
}
