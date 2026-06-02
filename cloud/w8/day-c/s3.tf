resource "aws_s3_bucket" "terraform_state"{
    bucket = "nhannguyen-terraform-state"
    force_destroy = true
}

resource "aws_s3_bucket_versioning" "versioning" {
    bucket = aws_s3_bucket.terraform_state.id
    versioning_configuration {
        status = "Enabled"
    }
}