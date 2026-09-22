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
