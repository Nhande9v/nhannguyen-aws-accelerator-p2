module "my_artifact_storage" {
  source = "./modules/aws_s3_artifact"

  bucket_name = var.artifact_bucket_name
  environment = "development"
}