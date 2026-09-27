output "api_endpoint" {
  value       = aws_apigatewayv2_api.main.api_endpoint
  description = "フロントエンドがAPI呼び出し先として使うベースURL"
}
