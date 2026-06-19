resource "aws_macie2_account" "macie" {
    status = "ENABLED"
    finding_publishing_frequency =  "FIFTEEN_MINUTES"
}

# Tự động quét dữ liệu nhạy cảm 
resource "aws_macie2_classification_job" "macie_daily_job" {
    depends_on = [ aws_macie2_account.macie ]
    name       = "macie-onetime-scan-${var.environment}"
    job_type   = "ONE_TIME"
    job_status = "RUNNING"
  
    s3_job_definition {
      bucket_definitions {
        account_id = data.aws_caller_identity.current.account_id
        buckets = [var.bucket_id]
      }
    }
    description = "Job tu dong quet du lieu nhay cam hang ngay cho moi truong ${var.environment}"
}

data "aws_caller_identity" "current" {}