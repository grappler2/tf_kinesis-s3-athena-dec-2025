# athena.tf

resource "aws_s3_bucket" "athena_results" {
  bucket = "my-app-logs-${var.account_id}-athena-results"
}

resource "aws_s3_bucket_lifecycle_configuration" "athena_results_lifecycle" {
  bucket = aws_s3_bucket.athena_results.id

  rule {
    id     = "delete-old-queries"
    status = "Enabled"

    expiration {
      days = 30
    }
  }
}

resource "aws_athena_workgroup" "logs_queries" {
  name = "app-logs-workgroup"

  configuration {
    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/queries/"
    }
  }
}
