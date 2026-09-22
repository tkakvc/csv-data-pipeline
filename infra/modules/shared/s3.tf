# 【まずここを読む】このファイルの読み方
#
# Terraformのコードは基本的に全部この形をしている。
#
#   resource "リソースタイプ" "このコード内だけで使うローカルな名前" {
#     設定項目 = 値
#   }
#
# 「リソースタイプ」（例：aws_s3_bucket）はAWS側で決まっている名前で、ここは覚える必要はない
# （分からなくなったらTerraform Registry（registry.terraform.io）で検索すれば出てくる）。
# 「ローカルな名前」（例："csv"）は自分で好きに付ける名前で、他の場所から
# aws_s3_bucket.csv のように「リソースタイプ.ローカルな名前」の形で参照するために使う。
#
# 【重要・低優先度の見分け方】
# コンソールなら「バケットを作る」画面1つで済むところが、Terraformでは
# aws_s3_bucket・aws_s3_bucket_versioning・aws_s3_bucket_cors_configuration...と
# 設定項目ごとに別々のresourceブロックに分かれている。これはTerraform（というかAWSのAPI）の
# 決まり事であって、設計判断ではない。なので「なぜ分かれているか」を考える必要はなく、
# 「バケット1個につき、設定の種類の数だけresourceブロックが並ぶ」とだけ理解すれば十分。
# 個々の設定値（true/falseの中身等）も、docs/security.mdで既に決めた内容をそのまま書き写した
# だけなので、1行ずつ意味を深追いする必要はない。
#
# 逆に時間をかけて理解する価値があるのはこの2つだけ：
#   ①resource同士がどう参照し合っているか（例：aws_s3_bucket.csv.id という書き方）
#   ②jsonencode(...) を使ったIAMポリシー・バケットポリシーの組み立て方（64-84行目）

# 今このコードを実行している人のAWSアカウントIDを、AWSに問い合わせて取得する。
# variableにしてtfvarsで渡す方式だと、他の誰かがこのコードを別アカウントで使い回した時に
# 値の書き換えを忘れるリスクがあるが、この方式なら常に「実際に認証しているアカウント」の
# IDが自動的に入るため、そのリスクが無い。
data "aws_caller_identity" "current" {}

# CSV保存バケットの本体。
# 「本体」と言っているのは、これがバケットという「モノ」自体を作るresourceだから。
# この下に続くresourceたちは、このバケットに対する「設定の追加」でしかない。
resource "aws_s3_bucket" "csv" {
  # 末尾を「-account_id-region-an」の形にすると、AWSが新しく導入した
  # 「アカウントリージョン名前空間バケット」という別種のバケットだと誤認識され、
  # 通常のCreateBucketが x-amz-bucket-namespace ヘッダー必須のエラーで弾かれる。
  # そのためbucket-nameとaccount_id/regionの間に別の単語を挟み、そのパターンを避けている。
  bucket = "${var.project_name}-bucket-store-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
}

# 【優先度低・設定値の中身は既に決定済み】パブリックアクセスブロック＝「誰でも見られる状態」を防ぐ設定。
# docs/security.md 指摘4で「全部trueにする」と既に決めている。ここでは以下の1点だけ理解すればよい：
#   bucket = aws_s3_bucket.csv.id という行が「①」の例。
#   「csvという名前を付けたバケットのid（実際に作られた後に確定する識別子）を、
#    このpublic_access_block設定の対象として指定する」という、resource間の紐付けを表している。
#   コンソールで言えば「どのバケットの設定画面を開いているか」に相当する部分。
resource "aws_s3_bucket_public_access_block" "csv" {
  bucket = aws_s3_bucket.csv.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# 【優先度低】保存時暗号化の設定（docs/security.md 指摘4）。「AES256（＝SSE-S3）を使う」と決定済みの値をそのまま書いているだけ
resource "aws_s3_bucket_server_side_encryption_configuration" "csv" {
  bucket = aws_s3_bucket.csv.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# 【優先度低】バージョニング（誤って上書き・削除したファイルを復元できるようにする設定。docs/security.md 指摘4）
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

# 【優先度低】csvバケットと全く同じ内容（コピー＆ペースト元も同じ）。csvバケット側の説明を参照
resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# 【ここは理解する価値あり：jsonencode() の使い方】
#
# S3のバケットポリシーは、本来AWS側では「JSON形式の文章」として渡すものになっている。
# jsonencode({ ... }) は、{ }の中にHCL（Terraformの記法）で書いた内容を、
# 実行時にJSON文字列へ変換してくれる関数。手でJSON文字列を組み立てるより、
# 変数の埋め込み（下記のResource行など）がしやすいのでこの書き方が定番になっている。
#
# 中身が表しているルールは1つだけ：
#   「cloudfront.amazonaws.com（＝CloudFrontというAWSのサービスそのもの）からのリクエストのうち、
#    送信元が"このCloudFrontディストリビューション"（Condition以下）であるものに限り、
#    このバケットの中身を読む（s3:GetObject）ことを許可する」
#
# aws_cloudfront_distribution.frontend.arn という書き方が出てくるが、これは別ファイル
# （cloudfront.tf）で定義されているresourceを参照している。同じモジュール内なら、
# ファイルをまたいでいてもこの書き方でそのまま参照できる（importのような文が要らない）。
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
