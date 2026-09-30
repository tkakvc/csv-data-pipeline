# ④CSV取込Lambda（docs/api.md 3章）。REST APIではなく、S3のアップロードイベントから直接呼ばれる
# （EventBridge不使用。docs/architecture.md 7-3参照）。RDSに書き込むためVPC内に配置する。

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

resource "aws_lambda_permission" "ingest_s3" {
  statement_id   = "AllowS3Invoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.ingest.function_name
  principal      = "s3.amazonaws.com"
  source_arn     = var.csv_bucket_arn
  source_account = data.aws_caller_identity.current.account_id
}

# CSVバケット全体の通知設定はこの1リソースが一元管理する（バケット自体はmodules/shared側で作成）
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
