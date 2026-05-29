variable "environment"        { type = string }
variable "subnet_ids"         { type = list(string) }
variable "security_group_ids" { type = list(string) }
variable "kms_key_arn"        { type = string }
variable "alerts_sns_arn"     { type = string }

variable "tags" {
  type    = map(string)
  default = {}
}
