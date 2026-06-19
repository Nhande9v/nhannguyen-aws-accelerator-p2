resource "aws_s3_bucket" "macie_target" {
    bucket = "macie-sensitive-scan-bucket-${var.environment}-${random_string.suffix.result}"
    force_destroy = true
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}