variable "environment" {
   type = string
}

variable "bucket_id" {
    type =  string
    description = "ID của S3 cần scan"
}

variable "bucket_arn" {
    type = string
    description = "arn của S3 cần scan"
}