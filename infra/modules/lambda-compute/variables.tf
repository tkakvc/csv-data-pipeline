variable "project_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "frontend_domain" {
  type = string
}

variable "local_dev_origin" {
  type = string
}

variable "google_oauth_client_id" {
  type        = string
  description = "presign・summary Lambdaが、JWTのaudクレームの検証に使う"
}

variable "csv_bucket_name" {
  type = string
}

variable "csv_bucket_arn" {
  type = string
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "RDSに接続するLambda（ingest・summary）の配置先"
}

variable "lambda_security_group_id" {
  type = string
}

variable "db_secret_arn" {
  type = string
}
