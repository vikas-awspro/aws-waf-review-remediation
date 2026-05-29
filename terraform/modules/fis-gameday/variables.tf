variable "environment"        { type = string }
variable "rds_instance_arn"   { type = string }
variable "az_a_subnet_arns"   { type = list(string) }
variable "alb_5xx_alarm_arn"  { type = string }

variable "tags" {
  type    = map(string)
  default = {}
}
