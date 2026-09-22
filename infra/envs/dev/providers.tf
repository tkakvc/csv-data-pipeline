# 【このファイルの役割】「Terraform自体の設定」と「AWSへの接続方法」を書く場所。
# resourceブロック（実際に作るリソース）は1つも出てこない。土台の設定だけのファイル。

terraform {
  required_version = ">= 1.16.0"

  # required_providers：「このコードはAWS用のプラグイン（provider）を使う」という宣言。
  # ここのバージョン指定（"~> 5.0"＝5.x系ならOK）に基づいて、
  # 実行時にHashiCorpから対応するプラグインが自動ダウンロードされる（terraform init時）。
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# provider "aws" ブロック：「AWSのどのリージョンに、どんな設定で接続するか」を定義する。
# 通常は1個だけでよいが、今回は理由があって2個ある（下記コメント参照）。
provider "aws" {
  region = var.aws_region
}

# 【ここは理解する価値あり：プロバイダのエイリアス（alias）】
# CloudFrontで使うACM証明書は必ずus-east-1リージョンで発行する必要がある（AWSの仕様。他の
# リージョンで発行した証明書はCloudFrontにアタッチできない）。一方このプロジェクトの他のリソース
# （S3・RDS・Lambda等）は全部ap-northeast-1に置きたい。
#
# 1つのTerraformコードの中で「基本はap-northeast-1、証明書だけus-east-1」を両立させるために、
# alias = "us_east_1" という名前を付けた2個目のprovider "aws"を用意している。
# これを使いたいresourceには、providerという引数で aws.us_east_1 と明示的に指定する
# （modules/shared/cloudfront.tf の aws_acm_certificate がその例）。
# 何も指定しなければ、上のalias無しのprovider（region = var.aws_region）が使われる。
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
