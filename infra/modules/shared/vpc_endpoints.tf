# 【前提：なぜVPCエンドポイントが必要か】
# private1・private2のルートテーブル（network.tf）にはインターネットへの経路が無く、
# NATゲートウェイも置いていない（コストがかかるため）。そのため、このサブネットの中にいる
# Lambda・RDS・Fargateタスクは、インターネット経由でしかたどり着けないS3・Secrets Manager・
# ECR・CloudWatch Logsに、そのままでは絶対に到達できない。VPCエンドポイントは
# 「インターネットを経由せず、AWSのネットワークの中だけで完結する経路」でこれらの
# サービスに繋げる仕組み。NATを置かない設計を選んだ結果、使う先のAWSサービスの数だけ
# VPCエンドポイントが必要になっている（docs/network.md 5章参照）。
#
#   # | サービス           | タイプ    | 理由
#   1 | S3               | Gateway   | ルートテーブルに経路を1本追加するだけで無料。CSV/フロントエンドバケットへの到達に必要
#   2 | Secrets Manager   | Interface | Lambda・FargateがDB認証情報を取得するために必要
#   3 | ECR API / Docker  | Interface | Fargateタスクがコンテナイメージをpullするために必要
#   4 | CloudWatch Logs   | Interface | Lambda・Fargateがログを送るために必要
#
# 【理解する価値あり：Gateway型とInterface型の違い】
# Gateway型：ルートテーブルに「このサービス宛はここへ」という経路を1本追加するだけの仕組み。
#   ENIを使わないため無料。対応しているのはS3とDynamoDBの2つだけ。
# Interface型：サブネットの中にENI（ネットワークの差し込み口）を作り、そこにプライベートIPで
#   到達する仕組み。SGが必要で、ENI分の課金（時間＋データ処理量）がかかる。対応サービス数は多く、
#   Secrets Manager・ECR・CloudWatch Logsなど大半のAWSサービスがこちら。
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
  # 【理解する価値あり：for_eachとlocals】
  # Interfaceエンドポイントは4つとも「配置先サブネット」「SG」「private_dns_enabled」が
  # 全く同じで、呼び出すAWSサービス名だけが違う。同じ形のresourceブロックを4回コピペする
  # 代わりに、差分（サービス名）だけをmapにまとめてfor_eachに渡すと、1つのresourceブロックが
  # 4つのリソース（aws_vpc_endpoint.interface["secretsmanager"]など）に展開される。
  # サービスが増えても、このmapに1行足すだけで済む。
  interface_endpoint_services = {
    secretsmanager = "secretsmanager"
    ecr_api        = "ecr.api"
    ecr_dkr        = "ecr.dkr"
    logs           = "logs"
  }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoint_services

  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${var.aws_region}.${each.value}"
  # each.key（例："ecr_api"）はTerraform内部の識別名、each.value（例："ecr.api"）は
  # 実際のAWSサービス名の一部として使う値。この2つがmapのキー/値としてそれぞれ対応している。
  vpc_endpoint_type  = "Interface"
  subnet_ids         = [aws_subnet.private1.id, aws_subnet.private2.id]
  security_group_ids = [aws_security_group.secretsmanager_endpoint.id]
  # 【理解する価値あり】private_dns_enabled：これがtrueだと、Lambdaのコードが
  # 「secretsmanager.ap-northeast-1.amazonaws.com」という通常のアドレスをそのまま呼んでも、
  # VPC内部でそのアドレスがこのエンドポイントのプライベートIPに解決される（＝コードを
  # 一切変更せずに済む）。これが機能するにはVPC側のenable_dns_hostnames=true
  # （network.tf参照）が前提になっている。
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-${each.key}-endpoint"
  }
}
