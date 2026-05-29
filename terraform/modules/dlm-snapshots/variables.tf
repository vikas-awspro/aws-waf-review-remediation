variable "environment"    { type = string }
variable "alerts_sns_arn" { type = string }

variable "tags" {
  type    = map(string)
  default = {}
}
