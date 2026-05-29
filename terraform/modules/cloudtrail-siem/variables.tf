variable "environment"    { type = string }
variable "region"         { type = string }
variable "kms_key_arn"    { type = string }
variable "alerts_sns_arn" { type = string }

variable "splunk_hec_secret_id" {
  description = "Secrets Manager secret holding {endpoint, token} for Splunk HEC"
  type        = string
}
variable "firehose_failure_bucket_arn" { type = string }

variable "tags" {
  type    = map(string)
  default = {}
}
