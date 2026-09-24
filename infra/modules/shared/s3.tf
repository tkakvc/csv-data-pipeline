# 今このコードを実行している人のAWSアカウントIDを取得する。variableで渡す方式だと、
# 別アカウントで使い回す際に値の書き換えを忘れるリスクがあるため、常に実際に認証している
# アカウントのIDが自動的に入るdataソースを使う
data "aws_caller_identity" "current" {}

# CSV保存バケット（docs/security.md 指摘4・7に対応）
resource "aws_s3_bucket" "csv" {
  # 末尾を「-account_id-region-an」の形にすると、AWSの「アカウントリージョン名前空間バケット」
  # という別種のバケットだと誤認識され、通常のCreateBucketがエラーになるため、
  # bucket-nameとaccount_id/regionの間に別の単語を挟んでそのパターンを避けている
  bucket = "${var.project_name}-bucket-store-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
}

resource "aws_s3_bucket_public_access_block" "csv" {
  bucket = aws_s3_bucket.csv.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "csv" {
  bucket = aws_s3_bucket.csv.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "csv" {
  bucket = aws_s3_bucket.csv.id
  versioning_configuration {
    status = "Enabled"
  }
}

# CORS：ブラウザから署名付きURLへ直接PUTするために必要。AllowedOriginsはフロントエンドのドメインのみに限定する
resource "aws_s3_bucket_cors_configuration" "csv" {
  bucket = aws_s3_bucket.csv.id

  cors_rule {
    allowed_methods = ["PUT"]
    allowed_origins = ["https://${var.frontend_domain}", var.local_dev_origin]
    allowed_headers = ["*"]
  }
}

# フロントエンド配信バケット（CloudFront経由のみ公開。バケット自体への直接アクセスは許可しない）
resource "aws_s3_bucket" "frontend" {
  bucket = "${var.project_name}-frontend-store-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# CloudFrontのOACだけがこのバケットを読めるようにするポリシー
resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = jsonencode({
    Version = "2008-10-17"
    Id      = "PolicyForCloudFrontPrivateContent"
    Statement = [
      {
        Sid       = "AllowCloudFrontServicePrincipal"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.frontend.arn}/*"
        Condition = {
          ArnLike = {
            "AWS:SourceArn" = aws_cloudfront_distribution.frontend.arn
          }
        }
      }
    ]
  })
}
