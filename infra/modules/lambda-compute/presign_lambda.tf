# ⓪署名付きURL発行Lambda（POST /upload-url、docs/api.md 1章）。
# S3へのPutObjectだけを許可し、GetObject等は含めない（発行するだけで、自分でファイルを読み書きしない）。

data "aws_iam_policy_document" "presign_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "presign" {
  name               = "${var.project_name}-presign-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.presign_assume_role.json
}

resource "aws_iam_role_policy_attachment" "presign_basic" {
  role       = aws_iam_role.presign.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "presign" {
  name = "${var.project_name}-presign-lambda-policy"
  role = aws_iam_role.presign.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "${var.csv_bucket_arn}/uploads/*"
      }
    ]
  })
}

resource "aws_lambda_function" "presign" {
  function_name = "${var.project_name}-presign"
  role          = aws_iam_role.presign.arn
  runtime       = "python3.14"
  handler       = "handler.handler"
  timeout       = 3
  memory_size   = 128

  # backend/build.shがDocker（Lambdaの実行環境と同じLinuxベース）でビルドしたzip。
  # 事前にbuild.shを実行してbuild/presign.zipを作っておく必要がある
  filename         = "${path.module}/../../../backend/build/presign.zip"
  source_code_hash = filebase64sha256("${path.module}/../../../backend/build/presign.zip")

  environment {
    variables = {
      UPLOAD_BUCKET_NAME = var.csv_bucket_name
    }
  }

  tags = {
    Name = "${var.project_name}-presign"
  }
}

resource "aws_lambda_permission" "presign_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.presign.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*/upload-url"
}

resource "aws_apigatewayv2_integration" "presign" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.presign.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "presign" {
  api_id              = aws_apigatewayv2_api.main.id
  route_key           = "POST /upload-url"
  target              = "integrations/${aws_apigatewayv2_integration.presign.id}"
  authorization_type  = "CUSTOM"
  authorizer_id       = aws_apigatewayv2_authorizer.jwt.id
}
