# HTTP API本体。ルート・統合は各Lambdaのファイル（presign_lambda.tf・summary_lambda.tf）側に置く。
# JWT検証はLambda Authorizer（authorizer_lambda.tf）が共通で担当する。
resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["https://${var.frontend_domain}", var.local_dev_origin]
    allow_methods = ["GET", "POST"]
    allow_headers = ["authorization", "content-type"]
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true
}
