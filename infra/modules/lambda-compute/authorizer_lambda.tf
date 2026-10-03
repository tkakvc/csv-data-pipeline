# API GatewayのLambda Authorizer（JWT検証専用）。
#
# 【設計思想：なぜ検証だけを別Lambdaに切り出したか】
# 当初はpresign・summary各Lambdaが自分でJWTを検証していたが、summary用Lambdaは
# RDS接続のためVPC内に置く必要があり、VPC内はインターネットへの経路が無い
# （コスト都合でNATゲートウェイ不使用、vpc_endpoints.tf参照）。GoogleのJWKS（公開鍵）取得には
# インターネットアクセスが必須のため、summary用Lambda内でJWT検証をしようとすると、
# JWKS取得が永遠に終わらずLambdaのタイムアウトで強制終了する、という問題が実際に起きた。
# この検証処理だけをVPCに入れない専用Lambdaに切り出せば、RDS接続用Lambda自身は
# インターネットに出る必要が無くなり、矛盾が解消する。

# presign_lambda.tfと同じ順番（IAMロール→ポリシー→関数）。Lambdaは必ず何らかのIAMロールを
# 装って動く前提のため、ロールが無いと関数自体を作れない。

# 【理解する価値あり：assume_role_policyとは】
# 「誰がこのロールを装ってよいか」を決めるポリシー（信頼ポリシー）。presign・summaryと同じく
# 「lambda.amazonaws.com（Lambdaというサービスそのもの）だけがこのロールを使える」と書いている。
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

  # 【注意】summary_lambda.tf・ingest_lambda.tfにある vpc_config { ... } ブロックが、
  # ここには無い。書き忘れではなく意図的。このLambdaはRDSに繋がないのでVPCに入れる理由が無く、
  # 入れない方がインターネット（GoogleのJWKS）に出られる。
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

# 【理解する価値あり：REQUEST型・ペイロード形式2.0・シンプルレスポンス】
# authorizer_type = "REQUEST"：リクエストの中身（ヘッダー等）を丸ごとAuthorizer Lambdaに渡す方式
# （もう1つの"JWT"型はCognitoのようなAWS標準のJWT検証機構向けで、Googleの検証ロジックを
# 自分で書く今回には使えない）。
# authorizer_payload_format_version = "2.0" と enable_simple_responses = true の組み合わせで、
# Authorizer Lambdaの戻り値を { "isAuthorized": bool, "context": {...} } という単純な形にできる
# （付けないと、IAMポリシードキュメントを自分で組み立てる、より複雑な形式が必要になる）。
resource "aws_apigatewayv2_authorizer" "jwt" {
  api_id          = aws_apigatewayv2_api.main.id
  authorizer_type = "REQUEST"
  authorizer_uri  = aws_lambda_function.authorizer.invoke_arn
  # 【理解する価値あり】identity_sources：リクエストのどこを見てキャッシュ・判定するかの指定。
  # ここでは「Authorizationヘッダーの値が同じなら、同じ判定結果として扱ってよい」という目印になる
  # （authorizer_result_ttl_in_secondsを設定した場合、このキーでキャッシュが引かれる。今回は
  # キャッシュ期間を設定していないため、実質的には「必須ヘッダーが無いリクエストを先に弾く」
  # 役割が主）。
  identity_sources                  = ["$request.header.Authorization"]
  name                              = "${var.project_name}-jwt-authorizer"
  authorizer_payload_format_version = "2.0"
  enable_simple_responses           = true
}

# presign_lambda.tf・summary_lambda.tfと同じ考え方：関数を作っただけでは誰からも呼べない。
# source_arnで「このAPI Gatewayの、このAuthorizerからの呼び出しだけ」に絞っている
# （ルート用のaws_lambda_permissionはsource_arnの末尾がルート名だったが、Authorizer用は
# /authorizers/<authorizer_id> という専用の形式になる）。
resource "aws_lambda_permission" "authorizer_apigw" {
  statement_id  = "AllowAPIGatewayInvokeAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.authorizer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/authorizers/${aws_apigatewayv2_authorizer.jwt.id}"
}
