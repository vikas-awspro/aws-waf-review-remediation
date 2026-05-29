output "log_group_name"        { value = aws_cloudwatch_log_group.cloudtrail.name }
output "log_group_arn"         { value = aws_cloudwatch_log_group.cloudtrail.arn }
output "firehose_arn"          { value = aws_kinesis_firehose_delivery_stream.splunk.arn }
output "trail_to_cwlogs_role_arn" { value = aws_iam_role.trail_to_cwlogs.arn }
