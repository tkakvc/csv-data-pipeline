# ⑥読み取り専用Lambda（GET /summary、docs/api.md 2章）。
# RDSに接続するためVPC内（private1・private2）に配置し、DB認証情報をSecrets Managerから取得する。

data "aws_iam_policy_document" "summary_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "summary" {
  name               = "${var.project_name}-summary-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.summary_assume_role.json
}

resource "aws_iam_role_policy_attachment" "summary_basic" {
  role       = aws_iam_role.summary.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# VPC内のLambdaがENIを作成・削除するための権限（RDSに接続するために必要）
resource "aws_iam_role_policy_attachment" "summary_vpc" {
  role       = aws_iam_role.summary.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "summary" {
  name = "${var.project_name}-summary-lambda-policy"
  role = aws_iam_role.summary.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = var.db_secret_arn
      }
    ]
  })
}

resource "aws_lambda_function" "summary" {
  function_name = "${var.project_name}-summary"
  role          = aws_iam_role.summary.arn
  runtime       = "python3.14"
  handler       = "handler.handler"
  timeout       = 30
  memory_size   = 128

  filename         = "${path.module}/../../../backend/build/summary.zip"
  source_code_hash = filebase64sha256("${path.module}/../../../backend/build/summary.zip")

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }

  environment {
    variables = {
      DB_SECRET_ARN          = var.db_secret_arn
      GOOGLE_OAUTH_CLIENT_ID = var.google_oauth_client_id
    }
  }

  tags = {
    Name = "${var.project_name}-summary"
  }
}

resource "aws_lambda_permission" "summary_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.summary.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*/summary"
}

resource "aws_apigatewayv2_integration" "summary" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.summary.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "summary" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /summary"
  target    = "integrations/${aws_apigatewayv2_integration.summary.id}"
}
