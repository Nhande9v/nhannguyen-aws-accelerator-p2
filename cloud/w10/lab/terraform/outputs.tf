output "s3_bucket_name" {
  value = module.s3.bucket_name
}

output "sns_topic_arn" {
  value = module.sns.topic_arn
}