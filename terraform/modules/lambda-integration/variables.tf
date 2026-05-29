variable "environment"    { type = string }
variable "region"         { type = string }
variable "kms_key_arn"    { type = string }
variable "alerts_sns_arn" { type = string }

variable "tags" {
  type    = map(string)
  default = {}
}
