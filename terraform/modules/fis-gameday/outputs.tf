output "fis_role_arn" { value = aws_iam_role.fis.arn }
output "experiment_template_ids" {
  value = {
    terminate_ec2  = aws_fis_experiment_template.terminate_ec2.id
    rds_failover   = aws_fis_experiment_template.rds_failover.id
    az_partition   = aws_fis_experiment_template.az_partition.id
  }
}
