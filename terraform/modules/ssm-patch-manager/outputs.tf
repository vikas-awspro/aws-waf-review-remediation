output "patch_baseline_id" { value = aws_ssm_patch_baseline.windows.id }
output "window_id"         { value = aws_ssm_maintenance_window.patching.id }
output "patch_group"       { value = aws_ssm_patch_group.this.patch_group }
