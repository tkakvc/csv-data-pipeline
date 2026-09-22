# 【このファイルの役割】このenv（dev環境）で使う「変数の入れ物」を宣言する場所。
#
# variable "名前" { ... } は、プログラミング言語で言う「関数の引数の宣言」に近い。
# ここで宣言した名前は、同じディレクトリ内のどこからでも var.名前 という形で使える
# （main.tfでmodule "shared" に渡している var.project_name 等がその使用例）。
#
# defaultを書いておくと「値を指定しなければこれを使う」という初期値になる。
# 今はここで宣言した変数全部にdefaultがあるため、terraform.tfvarsは空でもよい状態になっている
# （defaultの無い変数を作った場合は、terraform.tfvarsで値を渡す必要がある）。

variable "project_name" {
  type    = string
  default = "cost-csv"
}

variable "aws_region" {
  type    = string
  default = "ap-northeast-1"
}

variable "frontend_domain" {
  type        = string
  description = "フロントエンドの公開ドメイン（CloudFrontのAlias・ACM証明書・CORSのAllowedOriginsに使う）"
  default     = "csv.okuyamat.click"
}

variable "route53_zone_name" {
  type        = string
  description = "既存のRoute53ホストゾーン名（新規作成はしない。career-support-appと共用のゾーン）"
  default     = "okuyamat.click"
}

variable "local_dev_origin" {
  type        = string
  description = "ローカル開発時のオリジン。S3のCORS AllowedOriginsに含める"
  default     = "http://localhost:5173"
}
