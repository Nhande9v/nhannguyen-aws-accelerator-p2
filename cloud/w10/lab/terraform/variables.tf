variable "aws_reigon" {
    type = string
    description = "AWS Region to deploy resources"
}

variable "environment" {
    type = string
    description = "Deployment environment (dev or prod)"
}

variable "email" {
    type = string
}