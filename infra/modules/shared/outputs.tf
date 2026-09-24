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
