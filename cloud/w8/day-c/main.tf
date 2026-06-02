module "my_artifact_storage" {
  source = ".   /modules/aws_s3_artifact" # Đường dẫn trỏ vào cái khuôn module con

  # Truyền tham số thực tế vào đây
  bucket_name = "nhannguyen-artifact-bucket"
  environment = "development"
}