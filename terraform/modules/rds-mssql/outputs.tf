output "instance_id"        { value = aws_db_instance.this.id }
output "endpoint"           { value = aws_db_instance.this.endpoint }
output "address"            { value = aws_db_instance.this.address }
output "port"               { value = aws_db_instance.this.port }
output "master_secret_arn"  { value = aws_db_instance.this.master_user_secret[0].secret_arn }
output "kms_key_arn"        { value = aws_kms_key.rds.arn }
output "security_group_id"  { value = var.security_group_ids[0] }
