# glue_catalog.tf

resource "aws_glue_catalog_database" "logs" {
  name = "app_logs_db"
}

resource "aws_glue_catalog_table" "logs" {
  name          = "request_response_logs"
  database_name = aws_glue_catalog_database.logs.name

  table_type = "EXTERNAL_TABLE"

  parameters = {
    "projection.enabled"          = "true"
    "projection.year.type"        = "integer"
    "projection.year.range"       = "2024,2030"
    "projection.month.type"       = "integer"
    "projection.month.range"      = "1,12"
    "projection.month.digits"     = "2"
    "projection.day.type"         = "integer"
    "projection.day.range"        = "1,31"
    "projection.day.digits"       = "2"
    "storage.location.template"   = "s3://${aws_s3_bucket.logs.bucket}/logs/year=$${year}/month=$${month}/day=$${day}/"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.logs.bucket}/logs/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    columns {
      name = "timestamp"
      type = "string"
    }

    columns {
      name = "uuid"
      type = "string"
    }

    columns {
      name = "level"
      type = "string"
    }

    columns {
      name = "logger"
      type = "string"
    }

    columns {
      name = "traceid"
      type = "string"
    }

    columns {
      name = "request"
      type = "struct<method:string,path:string,headers:map<string,string>,body:string,ipaddress:string>"
    }

    columns {
      name = "response"
      type = "struct<statuscode:int,headers:map<string,string>,body:string,durationms:int>"
    }

    columns {
      name = "environment"
      type = "string"
    }

    columns {
      name = "servicename"
      type = "string"
    }
  }

  partition_keys {
    name = "year"
    type = "int"
  }

  partition_keys {
    name = "month"
    type = "int"
  }

  partition_keys {
    name = "day"
    type = "int"
  }
}