output "bucket_id" {
  description = "Tra ve Name/ID cua S3 bucket vua tao tu module"
  value       = aws_s3_bucket.artifact.id
}

output "bucket_arn" {
  description = "Tra ve mã ARN cua S3 bucket vua tao tu module"
  value       = aws_s3_bucket.artifact.arn
}