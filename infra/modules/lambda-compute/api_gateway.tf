# 【設計の変遷：当初はLambda Authorizerを使わない方針だった】
# 当初はpresign・summary各Lambdaが自分でJWTを検証する方式にしていたが、summary用Lambdaを
# RDS接続のためVPC内に置いた結果、GoogleのJWKS取得（インターネットアクセスが必要）が
# タイムアウトする問題が発覚した。この解消のため、JWT検証だけをVPC外の専用Lambda
# （Authorizer）に切り出す方式に変更した（authorizer_lambda.tf参照）。

# HTTP API本体。ルート・統合は各Lambdaのファイル（presign_lambda.tf・summary_lambda.tf）側に置く
# （「1つのAPI」の中に複数の「ルート」があり、各ルートが1つの「統合」に紐づく、という階層）。
resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"

  # ブラウザの Same-Origin Policy 対策。フロントエンドのドメインとAPI Gatewayのドメインが
  # 違うため、ここで明示的に許可しないとブラウザ側がレスポンスをブロックする
  # （s3.tfのCORS設定と同じ理由）。
  cors_configuration {
    allow_origins = ["https://${var.frontend_domain}", var.local_dev_origin]
    allow_methods = ["GET", "POST"]
    allow_headers = ["authorization", "content-type"]
  }
}

# 【理解する価値あり：ステージ（stage）とは何か】
# API Gatewayは「API本体（ルートや統合の定義）」と「実際に外部に公開する入り口（ステージ）」が
# 分かれている。HTTP APIでは"$default"という特別な名前のステージを1つ使うのが定番で、
# auto_deploy = true にすると、ルート等を変更してterraform applyするたびに、
# 明示的な「デプロイ」操作をしなくても自動で公開される（REST API（v1）ではデプロイが
# 別ステップとして必要だったが、HTTP APIではこのステージ設定だけで済む）。
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true
}
