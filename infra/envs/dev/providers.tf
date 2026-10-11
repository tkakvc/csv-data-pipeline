# 【このファイルの役割】「Terraform自体の設定」と「AWSへの接続方法」を書く場所。
# resourceブロック（実際に作るリソース）は1つも出てこない。土台の設定だけのファイル。

terraform {
  required_version = ">= 1.16.0"

  # required_providers：「このコードはAWS用のプラグイン（provider）を使う」という宣言。
  # ここのバージョン指定に基づいて、実行時にHashiCorpから対応するプラグインが
  # 自動ダウンロードされる（terraform init時）。
  #
  # 【設計思想：なぜ5.x→6.xに上げたか】
  # 最初から6.xを使う計画だったわけではない。レイヤーEでaws_lambda_functionの
  # runtime = "python3.14" を書いた時、5.x系最新（5.100.0）ではこの文字列がまだ
  # バリデーションの許可リストに入っておらず、terraform validateがエラーになった
  # ことで初めて発覚した制約。ただ、エラーに押されて無条件にバージョンを上げるのではなく、
  # 「今すでにapply済みの各リソース型（aws_vpc・aws_db_instance等）が、6.xの
  # 破壊的変更一覧に載っていないか」を先に確認してから上げている。載っていれば、
  # 意図せず既存リソースが再作成される事故につながるため。
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # randomプロバイダはAWSに何も接続しない（APIキーやリージョンの設定が要らない）ため、
    # required_providersへの登録だけで済み、下のprovider "aws"のような設定ブロックは不要。
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # backend "s3"：tfstate（Terraformが管理するリソースの記録ファイル）の保存先を、
  # デフォルトのローカルファイルからS3に変える設定。
  # ローカルのままだと「PCの中の1ファイルが消えたら、83個のリソースの管理情報を全部失う」
  # リスクがあるため、S3に置いて事故に強くした。
  #
  # 【詰まった点】
  # - key = "./terraform.tfstate" のように先頭に "./" を付けると、S3のオブジェクト名に
  #   そのまま "./" が入ってしまい、コンソールの署名付きURL発行でエラーになった
  #   （キーはファイルパスではなく単なる文字列なので "./" は不要）
  # - backendブロックの中は var.aws_region のような変数を使えない（設定を読み込む段階が
  #   他のコードより早いため）。リテラル文字列で書く必要がある
  backend "s3" {
    bucket         = "cost-csv-bucket-tfstate-460677238703-ap-northeast-1-an"
    key            = "terraform.tfstate"
    region         = "ap-northeast-1"
    profile        = "default"
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
