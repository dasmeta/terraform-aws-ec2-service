# Reuse the approval channel for execution status, including rejected/timed-out runs.
# The topic owner must grant EventBridge Publish using notification_policy_statement.
resource "aws_cloudwatch_event_rule" "execution_status" {
  name = "${var.name}-eks-ami-status"
  event_pattern = jsonencode({
    source        = ["aws.ssm"]
    "detail-type" = ["EC2 Automation Execution Status-change Notification"]
    detail        = { Definition = [aws_ssm_document.promote.name] }
  })
  tags = var.tags
}

resource "aws_cloudwatch_event_target" "execution_status" {
  rule = aws_cloudwatch_event_rule.execution_status.name
  arn  = var.promotion.notification_arn
}
