output "dlq_arn"             { value = aws_sqs_queue.dlq.arn }
output "dlq_url"             { value = aws_sqs_queue.dlq.id }
output "dlq_send_policy_arn" { value = aws_iam_policy.dlq_send.arn }
output "reprocess_role_arn"  { value = aws_iam_role.reprocess.arn }
