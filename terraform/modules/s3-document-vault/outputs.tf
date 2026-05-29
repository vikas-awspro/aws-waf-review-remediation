output "bucket_arn"    { value = aws_s3_bucket.this.arn }
output "bucket_name"   { value = aws_s3_bucket.this.id }
output "crr_role_arn"  { value = aws_iam_role.crr.arn }
