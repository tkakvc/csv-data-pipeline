# 【このファイルの役割】このモジュール（shared）が外から受け取る変数の宣言。
# envs/dev/variables.tf と役割は同じだが、こちらは「モジュール側」の宣言という違いがある。
# defaultを書いていないので、呼び出し側（envs/dev/main.tf）が必ず全部の値を渡す必要がある。

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 【理解する価値あり】configuration_aliases：このモジュールの中でaws.us_east_1という
      # 名前のプロバイダを使いたい場合、モジュール側にもこの宣言が必要、というTerraformの決まり。
      # 「envs/dev/providers.tfで作ったus_east_1プロバイダを、このモジュールにも
      #  持ち込めるようにする」という許可のようなもの。実際に「渡す」操作自体は
      # envs/dev/main.tfのproviders = { aws.us_east_1 = aws.us_east_1 } の行で行っている。
      configuration_aliases = [aws.us_east_1]
    }
  }
}

variable "project_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "frontend_domain" {
  type = string
}

variable "route53_zone_name" {
  type = string
}

variable "local_dev_origin" {
  type = string
}
