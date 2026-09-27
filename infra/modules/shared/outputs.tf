# 【このファイルの役割】このモジュールの中で作ったリソースの値を、外（envs/dev側や、
# 将来追加する他のモジュール）から参照できるようにする「戻り値」の宣言。
#
# variable が「関数の引数」なら、output は「関数のreturn」に相当する。
# 例えば将来レイヤーE（Lambda）を書くとき、CSVバケット名が必要になるが、
# モジュールをまたいで直接 aws_s3_bucket.csv.id と書くことはできない
# （sharedモジュールの中の話は、外からは見えない）。代わりに
# module.shared.csv_bucket_name という形でこのoutputを経由して参照する。

output "csv_bucket_name" {
  value       = aws_s3_bucket.csv.id
  description = "後続レイヤー（Lambda等）から参照するCSV保存バケット名"
}

output "csv_bucket_arn" {
  value = aws_s3_bucket.csv.arn
}

output "frontend_bucket_name" {
  value = aws_s3_bucket.frontend.id
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.frontend.domain_name
}

output "vpc_id" {
  value       = aws_vpc.main.id
  description = "後続レイヤー（SG・VPCエンドポイント等）から参照するVPC ID"
}

output "private_subnet_ids" {
  value       = [aws_subnet.private1.id, aws_subnet.private2.id]
  description = "RDS・Lambda・Interfaceエンドポイントの配置先（private1, private2の順）"
}

output "private_route_table_ids" {
  value       = [aws_route_table.private1.id, aws_route_table.private2.id]
  description = "S3向けGatewayエンドポイントの関連付け先（private1, private2の順）"
}

output "lambda_security_group_id" {
  value       = aws_security_group.lambda.id
  description = "Lambda（レイヤーE）・バックフィルFargateタスク（レイヤーF）に付与するSG"
}

output "db_security_group_id" {
  value       = aws_security_group.db.id
  description = "RDS（レイヤーD）に付与するSG"
}

output "db_secret_arn" {
  value       = aws_secretsmanager_secret.db_credentials.arn
  description = "Lambda（レイヤーE）・バックフィルFargateタスク（レイヤーF）がDB接続情報を取得するSecrets ManagerのARN"
}
