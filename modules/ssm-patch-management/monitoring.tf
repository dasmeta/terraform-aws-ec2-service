# Reuse the approval channel for execution status, including rejected/timed-out runs.
# The topic owner must grant EventBridge Publish using notification_policy_statement.
resource "aws_cloudwatch_event_rule" "execution_status" {
  count = var.production == null ? 0 : 1
  name  = "${var.name}-ec2-patch-status"
  event_pattern = jsonencode({
    source        = ["aws.ssm"]
    "detail-type" = ["EC2 Automation Execution Status-change Notification"]
    detail        = { Definition = [aws_ssm_document.approved_install[0].name] }
  })
  tags = var.tags
}

resource "aws_cloudwatch_event_target" "execution_status" {
  count = var.production == null ? 0 : 1
  rule  = aws_cloudwatch_event_rule.execution_status[0].name
  arn   = try(var.production.notification_arn, null)
}

resource "aws_cloudwatch_event_rule" "nonproduction_status" {
  count = var.nonproduction_notification_arn == null ? 0 : 1
  name  = "${var.name}-nonproduction-patch-status"
  event_pattern = jsonencode({
    source        = ["aws.ssm"]
    "detail-type" = ["Maintenance Window Execution State-change Notification"]
    detail        = { "window-id" = [for key, window in aws_ssm_maintenance_window.this : window.id if key != "production"] }
  })
  tags = var.tags
}

resource "aws_cloudwatch_event_target" "nonproduction_status" {
  count = var.nonproduction_notification_arn == null ? 0 : 1
  rule  = aws_cloudwatch_event_rule.nonproduction_status[0].name
  arn   = var.nonproduction_notification_arn
}
