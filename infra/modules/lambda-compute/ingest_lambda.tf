# ④CSV取込Lambda（docs/api.md 3章）。REST APIではなく、S3のアップロードイベントから
# 直接呼ばれる（EventBridge不使用。docs/architecture.md 7-3参照）。
#
# 【設計思想：呼び出し元が人間ではなくS3になると、権限の考え方が鏡合わせになる】
# presign・summaryは「API Gatewayが呼ぶ権限」を渡したが、このLambdaを呼ぶのはS3
# （ファイルがアップロードされた、というイベント）。principalが変わるだけで、
# 「まず呼び出し許可を渡し、その後に実際の連携（通知設定）を書く」という順番の考え方は同じ。

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "ingest_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ingest" {
  name               = "${var.project_name}-ingest-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.ingest_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ingest_basic" {
  role       = aws_iam_role.ingest.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "ingest_vpc" {
  role       = aws_iam_role.ingest.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# このLambdaが実際にやる2つの操作（S3から読む・DBシークレットを読む）にちょうど対応する権限だけ
resource "aws_iam_role_policy" "ingest" {
  name = "${var.project_name}-ingest-lambda-policy"
  role = aws_iam_role.ingest.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${var.csv_bucket_arn}/uploads/*"
      },
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = var.db_secret_arn
      }
    ]
  })
}

resource "aws_lambda_function" "ingest" {
  function_name = "${var.project_name}-ingest"
  role          = aws_iam_role.ingest.arn
  runtime       = "python3.14"
  handler       = "handler.handler"
  timeout       = 30
  memory_size   = 128

  filename         = "${path.module}/../../../backend/build/ingest.zip"
  source_code_hash = filebase64sha256("${path.module}/../../../backend/build/ingest.zip")

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }

  environment {
    variables = {
      DB_SECRET_ARN = var.db_secret_arn
    }
  }

  tags = {
    Name = "${var.project_name}-ingest"
  }
}

# 【設計思想：source_accountまで指定する理由】
# source_arn（バケットのARN）だけでも「そのバケットからの呼び出し」に絞れるが、
# 万が一"別のAWSアカウント"に同名のバケットが存在した場合、そちらからも呼べてしまう
# 可能性が理論上ある（confused deputy＝騙された代理人、と呼ばれる問題）。
# source_accountでアカウントIDも合わせて固定することで、この抜け道を塞いでいる。
resource "aws_lambda_permission" "ingest_s3" {
  statement_id   = "AllowS3Invoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.ingest.function_name
  principal      = "s3.amazonaws.com"
  source_arn     = var.csv_bucket_arn
  source_account = data.aws_caller_identity.current.account_id
}

# 【設計思想：この通知設定は「一元管理型」のリソース】
# aws_s3_bucket_notificationは1バケットに対して1つしか存在できない（設定を「差分追加」
# するのではなく、そのバケット全体の通知設定を丸ごと上書きする形のリソース）。もし将来
# 別のLambda用に、どこか別の場所で同じバケット宛のaws_s3_bucket_notificationを
# もう1つ書いてしまうと、互いの設定を消し合う事故になる。だからこのバケットの通知設定は
# ここ1箇所だけで管理する、というルールを決めている。
#
# depends_onで明示的に権限（上のresource）を先に作らせているのは、権限が無い状態で
# 通知設定だけ先にできてしまうと、実際にイベントが飛んだ瞬間だけ権限エラーになる、
# という分かりにくい壊れ方を避けるため。
resource "aws_s3_bucket_notification" "csv_uploads" {
  bucket = var.csv_bucket_name

  lambda_function {
    lambda_function_arn = aws_lambda_function.ingest.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "uploads/"
    filter_suffix       = ".csv"
  }

  depends_on = [aws_lambda_permission.ingest_s3]
}
