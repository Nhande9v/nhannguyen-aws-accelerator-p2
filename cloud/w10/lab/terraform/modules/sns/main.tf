resource "aws_sns_topic" "macie_alerts" {
    name = "macie-alerts-topic-${var.environment}"
}

resource "aws_sns_topic_subscription" "email_sub" {
    topic_arn = aws_sns_topic.macie_alerts.arn
    protocol = "email"
    endpoint =  var.email
}