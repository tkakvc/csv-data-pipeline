# ⓪署名付きURL発行Lambda（POST /upload-url、docs/api.md 1章）。
#
# 【設計思想：なぜIAMロールがLambda関数より先に出てくるか】
# このファイルの「主役」は一見aws_lambda_function（実際に動くコード）だが、書く順番は
# 逆になる。AWSの仕組みとして、Lambdaは「必ず何らかのIAMロールを装って動く」ことが前提で、
# ロールが存在しない状態ではLambda関数自体を作成できない。だからコードもIAMロール→
# ポリシー→関数、という依存の順に並んでいる。

data "aws_iam_policy_document" "presign_assume_role" {
  # 【理解する価値あり：assume_role_policyとは】
  # 「誰がこのロールを装ってよいか」を決めるポリシー（信頼ポリシー）。ここでは
  # 「lambda.amazonaws.com（Lambdaというサービスそのもの）だけがこのロールを使える」
  # と書いている。裏を返すと、このロールはLambda以外（例：EC2）からは絶対に使えない。
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

# CloudWatch Logsへの書き込み権限（AWS管理の定番ポリシー）。これが無いと、Lambdaの
# エラー・ログが一切残らず、デバッグができなくなる。
resource "aws_iam_role_policy_attachment" "presign_basic" {
  role       = aws_iam_role.presign.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# 【設計思想：権限の範囲を「実際にやる1個の操作」に絞る】
# このLambdaが実際にやることは「署名付きURLを発行するだけ」で、自分でファイルを
# 読み書きするわけではない（core/db.pyのような他の処理も無い）。それでも念のためと
# 権限を広く（s3:*等）与えるのではなく、実コードが呼ぶ1個のboto3呼び出し
# （generate_presigned_url("put_object", ...)）にちょうど対応する s3:PutObject だけ、
# かつパスも uploads/ 配下だけに絞っている。理由は「この関数が乗っ取られた場合の
# 被害範囲を、実際にやっていること以上に広げないため」。
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

  # 【理解する価値あり：filenameとsource_code_hash】
  # filenameはアップロードするzipのパス。source_code_hashは「今のzipの中身のハッシュ値」で、
  # 前回applyした時と値が変わっていればTerraformが「コードが更新された」と判断し、
  # Lambdaのコードを再アップロードする（変わっていなければ何もしない）。
  # zip自体はTerraformが作るのではなく、backend/build.shが事前に作ったものを参照するだけ
  # （backend/build.sh参照。なぜTerraformの中でビルドしないかもそちらに書いてある）。
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

# 【設計思想：関数を作った後も、まだ誰も呼べない】
# Lambda関数はデフォルトでは誰からも呼び出せない。API Gateway側で統合（integration）や
# ルートを設定しても、それだけでは「呼び出す権限」にはならない。ここを飛ばすと、
# 見た目は正しく繋がっているのに、実際にリクエストが来た瞬間だけ403で落ちる、という
# 分かりにくい壊れ方をする。だから「呼んでいいという許可（この後述resource）」を先に
# 作ってから、実際の統合・ルートを書く、という順番にしている。
resource "aws_lambda_permission" "presign_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.presign.function_name
  principal     = "apigateway.amazonaws.com"
  # source_arnで「このAPI Gatewayの、POST /upload-urlというルートからの呼び出しだけ」に
  # 絞っている。単にprincipalだけ許可すると、他の（無関係な）API Gatewayからも
  # 呼べてしまうことになる。
  source_arn = "${aws_apigatewayv2_api.main.execution_arn}/*/*/upload-url"
}

resource "aws_apigatewayv2_integration" "presign" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.presign.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "presign" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /upload-url"
  target    = "integrations/${aws_apigatewayv2_integration.presign.id}"

  # このルートに来たリクエストは、本体を呼ぶ前にまずauthorizer_lambda.tfのAuthorizerを通す
  authorization_type = "CUSTOM"
  authorizer_id       = aws_apigatewayv2_authorizer.jwt.id
}
