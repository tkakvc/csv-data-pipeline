# NATゲートウェイを置かない設計のため、プライベートサブネットからAWSサービスに到達する手段として
# VPCエンドポイントを使う（docs/network.md 5章参照）。
#
#   # | サービス           | タイプ    | 理由
#   1 | S3               | Gateway   | ルートテーブルに経路を1本追加するだけで無料。CSV/フロントエンドバケットへの到達に必要
#   2 | Secrets Manager   | Interface | Lambda・FargateがDB認証情報を取得するために必要
#   3 | ECR API / Docker  | Interface | Fargateタスクがコンテナイメージをpullするために必要
#   4 | CloudWatch Logs   | Interface | Lambda・Fargateがログを送るために必要
#
# S3向けはGatewayタイプなのでルートテーブルへの関連付けのみで完結する。
# 2〜4はInterfaceタイプ（ENIを使う）のため、配置するサブネットとSGが必要。
# SGは新規に作らず、Secrets Manager用に作ったSG（443番をlambda-sgから許可済み）を使い回す
# （3〜4も同じ443番のHTTPS通信のため、追加のSGルールが不要）

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private1.id, aws_route_table.private2.id]

  tags = {
    Name = "${var.project_name}-s3-endpoint"
  }
}

locals {
  # Interfaceエンドポイントは4つとも「配置先サブネット」「SG」が全く同じで、
  # 呼び出すAWSサービス名だけが違うため、for_eachでまとめて書く
  interface_endpoint_services = {
    secretsmanager = "secretsmanager"
    ecr_api        = "ecr.api"
    ecr_dkr        = "ecr.dkr"
    logs           = "logs"
  }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoint_services

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private1.id, aws_subnet.private2.id]
  security_group_ids  = [aws_security_group.secretsmanager_endpoint.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-${each.key}-endpoint"
  }
}
