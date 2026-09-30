# レイヤーA：S3（CSV保存・フロントエンド配信）・CloudFront
module "shared" {
  source = "../../modules/shared"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  project_name      = var.project_name
  aws_region        = var.aws_region
  frontend_domain   = var.frontend_domain
  route53_zone_name = var.route53_zone_name
  local_dev_origin  = var.local_dev_origin
}

# レイヤーE：IAMロール・Lambda3本・API Gateway
module "lambda_compute" {
  source = "../../modules/lambda-compute"

  project_name             = var.project_name
  aws_region               = var.aws_region
  frontend_domain          = var.frontend_domain
  local_dev_origin         = var.local_dev_origin
  google_oauth_client_id   = var.google_oauth_client_id
  csv_bucket_name          = module.shared.csv_bucket_name
  csv_bucket_arn           = module.shared.csv_bucket_arn
  private_subnet_ids       = module.shared.private_subnet_ids
  lambda_security_group_id = module.shared.lambda_security_group_id
  db_secret_arn            = module.shared.db_secret_arn
}
