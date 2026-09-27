# ⑥読み取り専用Lambda（GET /summary、docs/api.md 2章）。
# presign_lambda.tfと同じ「IAMロール→ポリシー→関数→呼び出し許可→API Gateway」の順番だが、
# RDSに接続する分、presignには無かった制約が2つ増える（下記コメント参照）。

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

# 【設計思想：制約①】VPCの中にLambdaを置く（vpc_configを設定する）と、Lambda自身に
# 「ENI（ネットワークの差し込み口）を作る・調べる・消す」ためのEC2 API権限が別途必要になる。
# これはAWS側の決まった仕様で、AWSLambdaVPCAccessExecutionRoleという専用の管理ポリシーを
# 付けないと、コールドスタート時にENI作成そのものが権限エラーで失敗する
# （vpc_configを書いただけでは足りない、という分かりにくい点）。
resource "aws_iam_role_policy_attachment" "summary_vpc" {
  role       = aws_iam_role.summary.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# 【設計思想：制約②、かつ実際に見つけた既存のバグ】
# このLambdaが必要とするのは「DBのシークレットを1個読む」権限だけ。それだけなのに、
# 旧コンソール版のIAMポリシー（cost-csv-summary-lambda-policy）は
# Action: secretsmanager:GetSecretValue に対して Resource がS3のARNになっている
# 書き間違いがあった（コピペではなく「このLambdaは何を読む必要があるか」から
# 権限を組み立てたからこそ気づけたバグ）。ここでは正しくSecrets ManagerのARNを指定する。
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

  # RDSと同じVPC・同じプライベートサブネットに配置し、db-sgが許可しているlambda-sgを付ける
  # （modules/shared/security_groups.tf・network.tf参照）。
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
