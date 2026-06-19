output "dev_bucket_name" { 
    value = module.root.s3_bucket_name 
}
output "dev_sns_topic" { 
    value = module.root.sns_topic_arn 
}