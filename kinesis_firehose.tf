# kinesis_firehose.tf

resource "aws_kinesis_stream" "app_logs" {
  name             = "app-logs-stream"
  shard_count      = 2  # Adjust based on your throughput
  retention_period = 24  # hours

  tags = {
    Environment = "production"
  }
}

resource "aws_s3_bucket" "logs" {
  bucket = "my-app-logs-${var.account_id}"
}

resource "aws_s3_bucket_lifecycle_configuration" "logs_lifecycle" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 180
      storage_class = "GLACIER"
    }
  }
}

resource "aws_iam_role" "firehose_role" {
  name = "firehose-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "firehose.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "firehose_s3" {
  role = aws_iam_role.firehose_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "${aws_s3_bucket.logs.arn}",
          "${aws_s3_bucket.logs.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:GetShardIterator",
          "kinesis:GetRecords",
          "kinesis:ListShards"
        ]
        Resource = aws_kinesis_stream.app_logs.arn
      },
      {
        Effect = "Allow"
        Action = [
          "glue:GetTable",
          "glue:GetTableVersion",
          "glue:GetTableVersions"
        ]
        Resource = [
          "arn:aws:glue:*:${var.account_id}:catalog",
          "arn:aws:glue:*:${var.account_id}:database/${aws_glue_catalog_database.logs.name}",
          "arn:aws:glue:*:${var.account_id}:table/${aws_glue_catalog_database.logs.name}/${aws_glue_catalog_table.logs.name}"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.firehose_logs.arn}:log-stream:${aws_cloudwatch_log_stream.firehose_s3_delivery.name}"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "firehose_logs" {
  name              = "/aws/kinesisfirehose/app-logs"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_stream" "firehose_s3_delivery" {
  name           = "S3Delivery"
  log_group_name = aws_cloudwatch_log_group.firehose_logs.name
}

resource "aws_kinesis_firehose_delivery_stream" "logs_to_s3" {
  name        = "app-logs-delivery-stream"
  destination = "extended_s3"

  depends_on = [aws_cloudwatch_log_group.firehose_logs, aws_cloudwatch_log_stream.firehose_s3_delivery]

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.app_logs.arn
    role_arn           = aws_iam_role.firehose_role.arn
  }

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose_role.arn
    bucket_arn = aws_s3_bucket.logs.arn

    # Dynamic partitioning by date and UUID prefix
    prefix              = "logs/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/uuid_prefix=!{partitionKeyFromQuery:uuid_prefix}/"
    error_output_prefix = "errors/!{firehose:error-output-type}/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"

    buffering_size     = 128  # MB
    buffering_interval = 300  # seconds (5 minutes)

    compression_format = "UNCOMPRESSED"  # or "SNAPPY" for faster queries

    # Convert to Parquet for better Athena performance
    data_format_conversion_configuration {
      enabled = true

      input_format_configuration {
        deserializer {
          open_x_json_ser_de {}
        }
      }

      output_format_configuration {
        serializer {
          parquet_ser_de {
            compression = "SNAPPY"
          }
        }
      }

      schema_configuration {
        database_name = aws_glue_catalog_database.logs.name
        table_name    = aws_glue_catalog_table.logs.name
        role_arn      = aws_iam_role.firehose_role.arn
      }
    }

    dynamic_partitioning_configuration {
      enabled = true
    }

    processing_configuration {
      enabled = true

      processors {
        type = "MetadataExtraction"

        parameters {
          parameter_name  = "JsonParsingEngine"
          parameter_value = "JQ-1.6"
        }

        parameters {
          parameter_name  = "MetadataExtractionQuery"
          parameter_value = "{uuid_prefix: .uuid[0:2]}"  # First 2 chars of UUID for partitioning
        }
      }

      processors {
        type = "AppendDelimiterToRecord"
      }
    }

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = "/aws/kinesisfirehose/app-logs"
      log_stream_name = "S3Delivery"
    }
  }
}