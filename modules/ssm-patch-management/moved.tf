# Preserve the baseline state address for consumers upgrading from the
# original module; without this move Terraform would replace the baseline.
moved {
  from = aws_ssm_patch_baseline.this
  to   = aws_ssm_patch_baseline.this[0]
}
