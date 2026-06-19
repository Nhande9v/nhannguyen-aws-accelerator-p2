resource "aws_cloudwatch_event_rule" "macie_finding" {
    name = "macie-findings-rule-${var.environment}"
    description = "Thu thập thông tin về dữ liệu nhạy cảm của Amazon Macie"

    event_pattern = jsonencode({
        "source": ["aws.macie"],
        "detail-type": ["Macie Finding"]
    })
}

resource "aws_cloudwatch_event_target" "sns" {
    rule = aws_cloudwatch_event_rule.macie_finding.name
    target_id = "SendTOSNS"
    arn = var.sns_topic_arn
}

#Cấp quyền cho EventBridge được gửi vào SNS.
resource "aws_sns_topic_policy" "default" {
arn = var.sns_topic_arn
policy = data.aws_iam_policy_document.sns_topic_policy.json
}

data "aws_iam_policy_document" "sns_topic_policy" {
    statement {
        effect = "Allow"
        actions = ["SNS:Publish"]
        principals {
            type = "Service"
            identifiers = ["events.amazonaws.com"]
        }
        resources = [var.sns_topic_arn]
            }
}