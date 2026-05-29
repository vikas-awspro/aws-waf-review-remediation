output "role_arn"             { value = aws_iam_role.app_tier.arn }
output "role_name"            { value = aws_iam_role.app_tier.name }
output "instance_profile_arn" { value = aws_iam_instance_profile.app_tier.arn }
output "instance_profile_name" { value = aws_iam_instance_profile.app_tier.name }
