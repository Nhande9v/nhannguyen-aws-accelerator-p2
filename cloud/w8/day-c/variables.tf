variable "aws_region" {
  description = "Vung trien khai ha tang AWS"
  type        = string
  default     = "ap-southeast-1"
}

variable "project_name" {
  description = "Ten du an dang thuc hien"
  type        = string
  default     = "xbrain-aws-accelerator"
}

variable "artifact_bucket_name" {
  description = "Ten cua S3 Bucket dung de chua san pham/artifact"
  type        = string
}