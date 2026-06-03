resource "aws_dynamodb_table" "terraform_lock"{
    name = "nhannguyen-terraform-lock"
    billing_mode = "PAY_PER_REQUEST"
    hash_key = "LockID"

    attribute {
        name = "LockID"
        type = "S"
    }
    tags = {
    Name        = "nhannguyen-terraform-lock"
    Project     = var.project_name
    ManagedBy   = "terraform"
  }
}