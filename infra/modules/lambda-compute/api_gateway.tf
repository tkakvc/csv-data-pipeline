# 【設計思想：Lambda Authorizerをここに書かない理由】
# docs/設計.md（旧版の検討時点）では「API GatewayのLambda Authorizerで守る」という案も
# 書かれていたが、実際に動いているコード（lambda_presign/handler.py・lambda_summary/handler.py）は
# ハンドラ自身の中でGoogleのJWKSを使ってJWTを検証している。API Gatewayレベルの認可設定
# （Authorizer）は実際には存在しない。設計ドキュメントの「理想形」ではなく「今のコードが
# 実際にやっていること」に合わせてTerraformを書くべきなので、ここではAuthorizerのリソースは
# 意図的に作らない（docs/api.mdの補足にもこの経緯が書かれている）。

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
