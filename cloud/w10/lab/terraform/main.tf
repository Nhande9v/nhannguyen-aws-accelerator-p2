module "s3" {
  source      = "./modules/s3"
  environment = var.environment
}

module "sns" {
  source      = "./modules/sns"
  environment = var.environment
  email = var.email
}

module "macie" {
  source      = "./modules/macie"
  environment = var.environment
  bucket_arn = module.s3.bucket_arn
  bucket_id = module.s3.bucket_name
}

module "eventbridge" {
  source        = "./modules/eventbridge"
  environment   = var.environment
  sns_topic_arn = module.sns.topic_arn
}