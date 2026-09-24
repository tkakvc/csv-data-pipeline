# 独自ドメイン（csv.okuyamat.click）でHTTPS配信するために必要な、ACM・Route53・CloudFrontを
# 1つの目的単位でまとめている（サービス単位ではなくファイルを分けない理由）。
#
#   # | 必要なもの                  | サービス   | 対応するリソース
#   1 | ドメイン所有者だと証明された証明書 | ACM       | aws_acm_certificate
#   2 | 証明書発行のための所有権証明（DNS検証） | Route53   | aws_route53_record.cert_validation
#   3 | 検証完了を待って証明書を確定させる  | (Terraform) | aws_acm_certificate_validation
#   4 | 配信の実体（CDN）           | CloudFront | aws_cloudfront_distribution
#   5 | CDNがS3に安全にアクセスする手段 | CloudFront | aws_cloudfront_origin_access_control
#   6 | 独自ドメイン→CDNへのDNSレコード | Route53   | aws_route53_record.frontend
#
# 以下は実際にterraform apply時にTerraformが処理する順番（1〜6）で並んでいる。

# 既存のRoute53ホストゾーン（career-support-appと共用）。新規作成はしない
data "aws_route53_zone" "main" {
  name = var.route53_zone_name
}

# AWS管理の「CachingOptimized」キャッシュポリシーを名前で参照する
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

# CloudFrontで使う証明書は必ずus-east-1で発行する（providers.tf参照）
resource "aws_acm_certificate" "frontend" {
  provider          = aws.us_east_1
  domain_name       = var.frontend_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# ACMのDNS検証用レコードを、証明書が要求する内容に沿って設置する
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.frontend.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = data.aws_route53_zone.main.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 300
}

# 検証完了を待ってから証明書を使用可能な状態として確定させる
resource "aws_acm_certificate_validation" "frontend" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.frontend.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

# S3をCloudFront経由でのみ読めるようにする接続設定（署名付きリクエストでアクセスする）
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "oac-${aws_s3_bucket.frontend.bucket}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFrontはユーザー（viewer）向けの接続とS3（origin）向けの接続を別々に持つため、
# viewer_certificateとoriginブロックでそれぞれ別の設定（証明書／OAC）を割り当てている
resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  default_root_object = "index.html"
  aliases             = [var.frontend_domain]
  http_version        = "http2"
  is_ipv6_enabled     = true
  price_class         = "PriceClass_All"

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  default_cache_behavior {
    target_origin_id       = aws_s3_bucket.frontend.bucket_regional_domain_name
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
  }

  # SPA（React Router）向け：存在しないパスもindex.htmlで受けてクライアント側でルーティングする
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }
  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.frontend.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# csv.okuyamat.click → CloudFrontディストリビューションへのAレコード（エイリアス）
resource "aws_route53_record" "frontend" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.frontend_domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.frontend.domain_name
    zone_id                = aws_cloudfront_distribution.frontend.hosted_zone_id
    evaluate_target_health = false
  }
}
