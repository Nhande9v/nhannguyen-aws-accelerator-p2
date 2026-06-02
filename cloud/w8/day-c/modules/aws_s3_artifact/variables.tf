variable "bucket_name" {
  description = "Ten cua S3 bucket"
  type        = string
}

variable "environment" {
  description = "Moi truong trien khai"
  type        = string
  default     = "dev"
}