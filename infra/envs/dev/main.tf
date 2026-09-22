# module { } は resource { } と同じ「名前付きの設定欄が並んだ箱」という書き方。
# resourceの設定欄（bucket等）はAWSが決め、moduleの設定欄（project_name等）は
# modules/shared/variables.tf で自分が決めている、という違いだけ。
#
# infra/envs/dev/variables.tf と infra/modules/shared/variables.tf は別ファイルで、
# 自動では繋がっていない。両方に project_name という同じ名前があるのは偶然ではなく、
# 下の「project_name = var.project_name」で明示的に繋いで初めて値が渡る。
#
# レイヤーA：S3（CSV保存・フロントエンド配信）・CloudFront
# 依存の薄いところから作るため、最初にこのレイヤーだけを対象にする。
module "shared" {
  source = "../../modules/shared"

  # 【ここは理解する価値あり】modules/shared/variables.tf側で
  # 「aws.us_east_1という名前のプロバイダを受け取る」と宣言しているため、
  # 呼び出す側のここでも「どのプロバイダをどの名前で渡すか」を明示する必要がある。
  # 書かないと「モジュールがus_east_1プロバイダを要求しているのに渡されていない」というエラーになる。
  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  # 左側＝modules/shared側の設定欄の名前、右側＝envs/dev側の変数から値を取り出す式
  project_name      = var.project_name
  aws_region        = var.aws_region
  frontend_domain   = var.frontend_domain
  route53_zone_name = var.route53_zone_name
  local_dev_origin  = var.local_dev_origin
}
