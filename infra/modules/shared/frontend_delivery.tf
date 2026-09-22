# 【なぜこのファイルにACM・Route53・CloudFrontの3種類が混ざっているか】
#
# 目標は1つ：「独自ドメイン（csv.okuyamat.click）で、HTTPSでフロントエンドを配信する」。
# Terraformのファイル分割は「1つのAWSサービスにつき1ファイル」という決まりではなく、
# 「1つの目的に必要なリソースをまとめる」という考え方の方が一般的。この目標を実現するには、
# 3つの別々のAWSサービスにまたがる、以下だけのモノが必要になる（だからファイル名も
# frontend_delivery.tf であり、cloudfront.tf ではない）。
#
#   # | 何が必要か                      | なぜ必要か                                            | サービス   | 対応するコード
#   1 | ドメイン所有者だと証明された証明書 | ブラウザがHTTPS接続時に「なりすましでない」と確認するため   | ACM       | aws_acm_certificate
#   2 | 証明書発行のための所有権証明      | 証明書は誰でも取得できると危険。DNSに指定レコードを置くことで
#     |                                | 「本当にこのドメインの持ち主か」を確認させる               | Route53   | aws_route53_record.cert_validation
#   3 | 検証完了を待つ仕組み             | 検証は非同期（すぐ終わらない）。実在のAWSリソースではなく、
#     |                                | Terraform独自の「終わるまで待つ」ための記法                | (Terraform) | aws_acm_certificate_validation
#   4 | 配信の実体（CDN）               | ユーザーにファイルを届け、キャッシュし、HTTPSを終端する本体   | CloudFront | aws_cloudfront_distribution
#   5 | CDNがS3に安全にアクセスする手段   | S3を非公開にしたまま、CloudFrontだけがアクセスできるようにする | CloudFront | aws_cloudfront_origin_access_control
#   6 | 独自ドメイン→CDNへの道しるべ     | csv.okuyamat.click と打たれた時、実際にどこに繋ぐべきかをDNSに登録 | Route53 | aws_route53_record.frontend
#  補 | 既存DNSゾーンの参照             | 2・6を書き込む対象(okuyamat.click)を新規作成せず参照するだけ | Route53   | data.aws_route53_zone
#  補 | キャッシュ設定を名前で参照        | 独自に作らず、AWS標準の定番設定を使う                     | CloudFront | data.aws_cloudfront_cache_policy
#
# 下の並び順は、実際にterraform apply実行時にTerraformが処理する順番と一致させている（1〜6）。

# 【理解する価値あり：dataブロック】
# resourceは「新しく作る」ものだが、dataは「既に存在するものを読み取るだけ」のブロック。
# このRoute53ホストゾーン（okuyamat.click）はcareer-support-appと共用の既存リソースで、
# 今回新規作成すると2つのポートフォリオでドメインが分裂してしまうため、
# 「既にある前提で、そのzone_id（識別子）だけ取得する」という意味でdataを使っている。
data "aws_route53_zone" "main" {
  name = var.route53_zone_name
}

# AWSが最初から用意している「CachingOptimized」という定番キャッシュ設定を、名前で検索する
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

# CloudFrontで使う証明書は必ずus-east-1で発行する（providers.tf参照）
resource "aws_acm_certificate" "frontend" {
  provider          = aws.us_east_1
  domain_name       = var.frontend_domain
  validation_method = "DNS"

  # 【優先度低】lifecycle：Terraform自身の挙動を調整する特殊なブロック。
  # create_before_destroy = true は「証明書を作り直す場合、先に新しい証明書を作ってから
  # 古い証明書を消す」という順序を指定している（逆にすると、新しい証明書ができるまでの間
  # HTTPSが一時的に使えなくなる）。今回はほぼ関係ないが、証明書の定番の書き方として付けている。
  lifecycle {
    create_before_destroy = true
  }
}

# 【理解する価値あり：for_each とループ】
# 「aws_acm_certificate.frontend.domain_validation_options」は、2で申請した証明書に対して
# ACMが「このDNSレコードを置いてくれれば所有者と認めます」と返してくる情報（の一覧）。
# ドメインを1つしか指定していないので中身は1件だが、Terraformの書き方としては
# 「複数件あるかもしれないもの」として for_each で扱うのが定番になっている。
#
#   for_each = {
#     for dvo in ○○ : dvo.domain_name => { ... }
#   }
#
# という書き方は「○○の各要素(dvo)を、dvo.domain_nameをキーにした辞書に変換する」という意味。
# JSでいう配列.map()に近い。これにより、後から each.value.name のように「今扱っている
# 1件分」のデータを取り出せる。for_eachが1個だけなら、同じ内容を1回書けば済むように見えるが、
# 将来ドメインが増えた場合にコードを増やさず対応できるようにするための書き方。
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

# 検証完了を待ってから証明書を「使える状態」として確定させる。
# validation_record_fqdns の [for r in ... : r.fqdn] も上と同じ考え方のループ（一覧から1項目だけ抜き出す）
resource "aws_acm_certificate_validation" "frontend" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.frontend.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

# S3をCloudFront経由でのみ読めるようにするための接続設定（署名付きリクエストでS3にアクセスする）
# 詳しくは s3.tf の aws_s3_bucket_policy.frontend のコメント（OACの説明）を参照
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "oac-${aws_s3_bucket.frontend.bucket}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# 【前提：CloudFrontは「2つの別々の接続」の間に立っている】
#
#   [ユーザーのブラウザ] ---接続①---> [CloudFront] ---接続②---> [S3バケット]
#           これを"viewer側"と呼ぶ                これを"origin側"と呼ぶ
#
# viewer（英単語で「見る人」）＝サイトを見ているユーザーのブラウザのこと。
# origin（英単語で「発生源・出どころ」）＝本物のファイルを持っているS3バケットのこと。
# 2つは別々の通信なので、それぞれ別々にセキュリティ設定が必要になる。だから設定が2箇所に分かれる：
#   origin側の鍵 → 下のoriginブロックのorigin_access_control_id（4のOAC）
#   viewer側の証明書 → 下のviewer_certificateブロック（3の証明書）
resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  default_root_object = "index.html"
  # aliases（英単語で「別名」）：CloudFrontには自動でxxxxx.cloudfront.netという名前が
  # 割り振られるが、何もしなければその名前でしかアクセスできない。ここにcsv.okuyamat.clickを
  # 加えることで「この独自ドメインでアクセスされても私宛だと認識して」と登録している。
  # ただし独自ドメインを名乗るなら、その独自ドメイン宛の証明書が無いとブラウザに
  # なりすましを疑われて弾かれる。だからaliasesとviewer_certificateは必ずセットで機能する。
  aliases             = [var.frontend_domain]
  http_version        = "http2"
  is_ipv6_enabled     = true
  # 【優先度低】price_class：世界のどのエッジロケーションを使うか（コストと配信範囲のトレードオフ）。
  # "PriceClass_All" は全世界のエッジロケーションを使う設定
  price_class = "PriceClass_All"

  # origin：上の「前提」で説明した接続②（CloudFront→S3）側の設定。
  # domain_name/origin_idで「S3のどこから取得するか」、origin_access_control_idで
  # 「OACという鍵を使って安全にアクセスする」ことを指定している
  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  # default_cache_behavior：「どういうリクエストを許可し、どうキャッシュするか」の設定
  default_cache_behavior {
    target_origin_id       = aws_s3_bucket.frontend.bucket_regional_domain_name
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    # AWSが最初から用意している「CachingOptimized」という定番キャッシュ設定を、
    # 名前で検索して使う（UUIDを直接書くと、それが何なのかコードから読み取れなくなるため）
    cache_policy_id = data.aws_cloudfront_cache_policy.caching_optimized.id
  }

  # React Router（SPA）は存在しないパスも全部index.htmlで受けてクライアント側でルーティングするため、
  # S3が403/404を返した場合もindex.htmlを200で返す
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

  # 【優先度低】地理的アクセス制限。"none"＝制限しない（全世界からアクセス可）
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # viewer_certificate：上の「前提」で説明した接続①（ブラウザ→CloudFront）側の設定。
  # ユーザーがhttps://csv.okuyamat.clickにアクセスした瞬間、ブラウザに対してCloudFrontが
  # 「私は本当にcsv.okuyamat.clickです」と提示する証明書がこれ（acm_certificate_arnで3の証明書を指定）。
  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate_validation.frontend.certificate_arn
    # 【優先度低】ssl_support_method："sni-only"はSNI（1つのIPアドレスで複数ドメインの
    # 証明書を使い分ける仕組み）を使う設定。追加コストのかかる専用IP方式を使わない、という選択
    ssl_support_method = "sni-only"
    # 【優先度低】minimum_protocol_version：viewer側で許可する暗号化方式の最低バージョン
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# csv.okuyamat.click → CloudFrontディストリビューションへのAレコード（エイリアス）。
# これで最終的に「そのドメインにアクセスすると、このCloudFrontが応答する」という状態になる
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
