# VPC・サブネット・ルートテーブルの設計値は docs/network.md の確定値をそのまま使う。
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

  # Secrets Manager・ECR等のInterfaceエンドポイント（レイヤーCで追加）が
  # プライベートDNS名で名前解決できるようにするため、両方を有効化する
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

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

# パブリックサブネット2つで共用の1枚
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

# private1・private2はそれぞれ専用のルートテーブルを持つ。
# S3向けVPCエンドポイントのルートは、エンドポイント作成時（レイヤーC）に
# route_table_idsへの関連付けを通じて自動追加されるため、ここでは書かない
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
