variable "bucket_name" {
  description = "Ten cua S3 bucket duoc truyen tu ngoai root vao"
  type        = string
}

variable "environment" {
  description = "Moi truong trien khai (development, staging, production)"
  type        = string
  default     = "development"
}