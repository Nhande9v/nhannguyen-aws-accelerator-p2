output "state_bucket_arn" {
  value       = aws_s3_bucket.terraform_state.arn
}

output "artifact_bucket_final_name" {
  value       = module.my_artifact_storage.bucket_id
}