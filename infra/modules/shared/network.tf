# 【前提：VPCとは何か】
# VPC（Virtual Private Cloud）は、AWSの中に自分専用に切り出す「仮想的なネットワークの箱」。
# 箱の中はさらに「サブネット」という小部屋に区切って使う。今回は4部屋（public1・public2・
# private1・private2）に分け、それぞれ別のAZ（Availability Zone＝データセンターの単位）に
# 1部屋ずつ置いている（同じ部屋を2つのAZに置くことはできない。AZが違えば別のサブネットになる）。
#
# 【設計思想：そもそもなぜVPCの話から始まるのか】
# 出発点は「RDSは非公開にする」というセキュリティ側の方針（docs/security.md）。
# 非公開のRDSは、インターネットからは一切到達できない代わりに、同じVPCの中からしか繋げない。
# だから「RDSに繋ぐLambda（ingest・summary）も同じVPCの中に置く」ことが自動的に決まり、
# 「VPCの中に置く」以上サブネットが要り、サブネットを2種類（public/private）に分けるかどうかも
# ここで決める必要が出てくる、という一本道の連鎖。VPC自体が欲しかったわけではなく、
# 「RDSを非公開にする」という1つの決定が、このファイル全体を要求している。
#
# 【なぜ独自にVPCを設計したか（経緯）】
# 最初にVPCを明確に設計せずコンソール作業を進めた結果、RDSが実際に使うVPCとは別の
# （AWSアカウントのデフォルト）VPCに誤ってリソースを作ってしまう事故が過去にあった。
# 名前・CIDR等の具体値はdocs/network.mdを正として扱い、このファイルもその値をそのまま使う。
#
#   # | 必要なもの                              | サービス | 対応するリソース
#   1 | プロジェクト専用のネットワーク領域            | VPC   | aws_vpc
#   2 | パブリックサブネットの出入口               | VPC   | aws_internet_gateway
#   3 | RDS・Lambda・VPCエンドポイントの置き場所（4つ） | VPC   | aws_subnet
#   4 | パブリックサブネットの経路（→IGW、2つで共用）     | VPC   | aws_route_table / aws_route_table_association
#   5 | プライベートサブネットの経路（AZごとに専用）        | VPC   | aws_route_table / aws_route_table_association
#
# 以下は実際にterraform apply時にTerraformが処理する順番（1〜5）で並んでいる。

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  # 【理解する価値あり】enable_dns_hostnames：
  # VPCエンドポイント（レイヤーCで追加するSecrets Manager・ECR等のInterface型）は、
  # 「Lambdaがsecretsmanager.ap-northeast-1.amazonaws.comという普通のアドレスを呼んだら、
  # 裏でこっそりVPC内のエンドポイントに転送する」という仕組み（プライベートDNS）で動く。
  # この仕組みが有効になるには、VPC自体がDNSでの名前解決に対応している必要があり、
  # そのための2つのフラグがこれ。デフォルトはenable_dns_hostnames=falseなので、
  # 明示的にtrueにしないとレイヤーCのエンドポイントが機能しない。
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# 【理解する価値あり】インターネットゲートウェイ（IGW）：
# VPCという「壁で囲われた箱」と、外のインターネットをつなぐ唯一の出入り口。
# VPCを作った時点では自動では付いてこないので、明示的に作ってVPCにアタッチする。
# ただしIGWを作るだけでは何も起きない。「どのサブネットが、このIGWを経由してよいか」は
# 下のルートテーブルで別途指定する必要がある（4番）。
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# 【公開/非公開の違いは「ルートテーブル」で決まる】
# public1・public2とprivate1・private2は、サブネットのリソース定義自体には
# 「公開/非公開」を示す設定は無い。実際に公開/非公開を分けているのは、
# 後述のルートテーブルに「0.0.0.0/0（インターネット全体）宛の経路がIGWに向いているか」
# だけ。だからサブネットを見ただけでは公開/非公開は判断できず、
# 「どのルートテーブルに関連付けられているか」まで見る必要がある。
resource "aws_subnet" "public1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.0.0/20"
  availability_zone = "ap-northeast-1a"

  tags = {
    Name = "${var.project_name}-subnet-public1-ap-northeast-1a"
  }
}

resource "aws_subnet" "public2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.16.0/20"
  availability_zone = "ap-northeast-1c"

  tags = {
    Name = "${var.project_name}-subnet-public2-ap-northeast-1c"
  }
}

resource "aws_subnet" "private1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.128.0/20"
  availability_zone = "ap-northeast-1a"

  tags = {
    Name = "${var.project_name}-subnet-private1-ap-northeast-1a"
  }
}

resource "aws_subnet" "private2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.144.0/20"
  availability_zone = "ap-northeast-1c"

  tags = {
    Name = "${var.project_name}-subnet-private2-ap-northeast-1c"
  }
}

# 【理解する価値あり】ルートテーブルとルートテーブル関連付け（association）の2段構造：
# aws_route_table自体は「経路のルールの集まり」を作るだけで、単体ではどのサブネットにも
# 効果を持たない。aws_route_table_associationで「このサブネットには、このルートテーブルを
# 使わせる」と明示的に紐付けて初めて、そのサブネット内の通信に経路が適用される。
# public1とpublic2は同じ内容（0.0.0.0/0→IGW）で構わないので、1枚のルートテーブルを
# 2つのサブネットで共用している（3つ作る必要はない）。
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-rtb-public"
  }
}

resource "aws_route_table_association" "public1" {
  subnet_id      = aws_subnet.public1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public2" {
  subnet_id      = aws_subnet.public2.id
  route_table_id = aws_route_table.public.id
}

# 【なぜprivate1・private2は別々のルートテーブルなのか】
# 今の内容（IGWへの経路が無いだけ）は2つとも全く同じで、1枚に共用してもよさそうに見える。
# ただし将来「private1だけ特別な経路を足したい」といった分岐が起きたときに備えて、
# AZ単位で専用のルートテーブルを持たせるのがAWSでの定番の作り方になっている
# （実際、この設計もAWSの「VPCなど」ウィザードのデフォルトの作り方を踏襲している）。
#
# S3向けVPCエンドポイントのルートは、ここには書かない。エンドポイント作成時（レイヤーC）に
# route_table_idsへの関連付けを通じて、Terraformが自動でこのルートテーブルにルートを
# 追加してくれる（aws_route_tableのroute{}ブロックとは別の経路で追加される）。
resource "aws_route_table" "private1" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-rtb-private1"
  }
}

resource "aws_route_table" "private2" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-rtb-private2"
  }
}

resource "aws_route_table_association" "private1" {
  subnet_id      = aws_subnet.private1.id
  route_table_id = aws_route_table.private1.id
}

resource "aws_route_table_association" "private2" {
  subnet_id      = aws_subnet.private2.id
  route_table_id = aws_route_table.private2.id
}
