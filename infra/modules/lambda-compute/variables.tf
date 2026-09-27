# 【このファイルの役割】modules/shared/variables.tfと同じ役割（モジュールが外から受け取る変数の宣言）。
# このモジュールが分かれている理由：modules/sharedは公開版・非公開版で共通のインフラ、
# こちらはLambda（コンピュート層）だけを差し替え可能にするための区切り（docs/architecture.md 8章）。

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

# 【理解する価値あり：モジュールを分けると、値を手渡す必要が出てくる】
# csv_bucket_name等は全部modules/sharedの中で作られた値だが、モジュールをまたいで
# 直接aws_s3_bucket.csv.idのようには参照できない（sharedモジュールの中の話は外から見えない）。
# だからenvs/dev/main.tfが「module.shared.csv_bucket_name」という形でsharedのoutputを受け取り、
# それをこのモジュールのvariableとして改めて渡す、という中継が必要になる。
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
