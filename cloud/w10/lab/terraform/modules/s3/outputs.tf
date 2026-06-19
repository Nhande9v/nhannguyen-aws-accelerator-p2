output "bucket_name" {
    value =  aws_s3_bucket.macie_target.id
}

output "bucket_arn" {
    value =  aws_s3_bucket.macie_target.arn
}