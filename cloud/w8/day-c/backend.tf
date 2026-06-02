terraform{
    backend "s3" {
        bucket = "nhannguyen-terraform-state"
        key = "terraform.tfstate"
        region = "ap-southeast-1"
        dynamodb_table = "nhannguyen-terraform-lock"
        encrypt = true
    }
}