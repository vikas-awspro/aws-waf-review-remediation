variable "environment"          { type = string }
variable "engine_version"       { type = string  default = "15.00.4365.2.v1" }
variable "instance_class"       { type = string  default = "db.r5.xlarge" }   # PERF-01 rightsize
variable "allocated_storage_gb" { type = number  default = 2048 }
variable "iops"                 { type = number  default = 8000 }

variable "isolated_subnet_ids" { type = list(string) }
variable "security_group_ids"  { type = list(string) }

variable "enhanced_monitoring_role_arn" { type = string }

variable "tags" {
  type    = map(string)
  default = {}
}
