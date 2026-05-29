variable "environment"        { type = string }
variable "vpc_id"             { type = string }
variable "public_subnet_ids"  { type = list(string) }
variable "private_subnet_ids" { type = list(string) }

variable "alb_sg_id" { type = string }
variable "web_sg_id" { type = string }
variable "app_sg_id" { type = string }

variable "certificate_arn"           { type = string }
variable "access_log_bucket"         { type = string }
variable "app_instance_profile_name" { type = string }
variable "ebs_kms_key_arn"           { type = string }

variable "web_ami_id"    { type = string }
variable "app_ami_id"    { type = string }
variable "web_user_data" { type = string  default = "" }
variable "app_user_data" { type = string  default = "" }

variable "tags" {
  type    = map(string)
  default = {}
}
