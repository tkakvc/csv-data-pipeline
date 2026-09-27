variable "project_name" {
  type    = string
  default = "cost-csv"
}

variable "aws_region" {
  type    = string
  default = "ap-northeast-1"
}

variable "frontend_domain" {
  type        = string
  description = "フロントエンドの公開ドメイン（CloudFrontのAlias・ACM証明書・CORSのAllowedOriginsに使う）"
  default     = "csv.okuyamat.click"
}

variable "route53_zone_name" {
  type        = string
  description = "既存のRoute53ホストゾーン名（career-support-appと共用のゾーン。新規作成はしない）"
  default     = "okuyamat.click"
}

variable "local_dev_origin" {
  type        = string
  description = "ローカル開発時のオリジン。S3・API GatewayのCORS AllowedOriginsに含める"
  default     = "http://localhost:5173"
}

variable "google_oauth_client_id" {
  type        = string
  description = "presign・summary LambdaがJWTのaudクレーム検証に使うGoogle OAuthクライアントID（機密情報ではない）"
  default     = "1024331697396-4g9s6cgm30o46s0t200kbg3jj5scqd0q.apps.googleusercontent.com"
}
