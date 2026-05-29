variable "environment"    { type = string }
variable "region"         { type = string }
variable "alb_arn"        { type = string }
variable "kms_key_arn"    { type = string }
variable "alerts_sns_arn" { type = string }

variable "rule_action" {
  description = "count for 2-week baseline, then block. Per-rule override is via override_action — set 'count' or 'block'."
  type        = string
  default     = "count"

  validation {
    condition     = contains(["count", "block"], var.rule_action)
    error_message = "rule_action must be 'count' or 'block'"
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
