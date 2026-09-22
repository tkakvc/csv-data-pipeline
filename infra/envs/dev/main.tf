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
