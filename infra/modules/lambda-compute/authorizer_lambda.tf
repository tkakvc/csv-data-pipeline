# API GatewayのLambda Authorizer（JWT検証専用）。
#
# summary用LambdaはRDS接続のためVPC内に置く必要があるが、VPC内はNATゲートウェイ不使用の
# ためインターネットへの経路が無い。GoogleのJWKS取得にはインターネットアクセスが必須のため、
# summary用Lambda内でJWT検証をしようとするとタイムアウトする。検証処理だけをVPCに入れない
# 専用Lambdaに切り出すことで、RDS接続用Lambda自身はインターネットに出る必要が無くなる。

data "aws_iam_policy_document" "authorizer_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "authorizer" {
  name               = "${var.project_name}-authorizer-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.authorizer_assume_role.json
}

resource "aws_iam_role_policy_attachment" "authorizer_basic" {
  role       = aws_iam_role.authorizer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "authorizer" {
  function_name = "${var.project_name}-authorizer"
  role          = aws_iam_role.authorizer.arn
  runtime       = "python3.14"
  handler       = "handler.handler"
  timeout       = 5
  memory_size   = 128

  # vpc_configを設定しない（presign用Lambdaと同じく、VPC外のままインターネットに出られるようにする）。
  filename         = "${path.module}/../../../backend/build/authorizer.zip"
  source_code_hash = filebase64sha256("${path.module}/../../../backend/build/authorizer.zip")

  environment {
    variables = {
      GOOGLE_OAUTH_CLIENT_ID = var.google_oauth_client_id
    }
  }

  tags = {
    Name = "${var.project_name}-authorizer"
  }
}

# authorizer_type = "REQUEST"：リクエストの中身（ヘッダー等）を丸ごとAuthorizer Lambdaに渡す方式。
# payload_format_version = "2.0" + enable_simple_responses = true で、戻り値を
# { "isAuthorized": bool, "context": {...} } という単純な形にできる。
resource "aws_apigatewayv2_authorizer" "jwt" {
  api_id                             = aws_apigatewayv2_api.main.id
  authorizer_type                    = "REQUEST"
  authorizer_uri                     = aws_lambda_function.authorizer.invoke_arn
  identity_sources                   = ["$request.header.Authorization"]
  name                                = "${var.project_name}-jwt-authorizer"
  authorizer_payload_format_version  = "2.0"
  enable_simple_responses            = true
}

resource "aws_lambda_permission" "authorizer_apigw" {
  statement_id  = "AllowAPIGatewayInvokeAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.authorizer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/authorizers/${aws_apigatewayv2_authorizer.jwt.id}"
}
