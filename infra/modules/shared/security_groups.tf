# 【前提：セキュリティグループ（SG）とは何か】
# SGは「このリソースへの通信を、誰から・どのポートで許可するか」を書いたルールの集まり。
# サブネットのルートテーブル（network.tf）が「どこに向かう経路があるか」を決めるのに対し、
# SGは「その経路が繋がった上で、実際に通信していいかどうか」を決める、もう1段別のチェック。
# 経路（ルートテーブル）があってもSGで拒否されれば通信は成立しない。
#
# 各SGの役割（docs/network.md 4章参照）：
#   cost-csv-lambda-sg                  : Lambda・Fargateタスクに付与する送信元SG。インバウンドは持たない
#   cost-csv-db-sg                      : RDS用。lambda-sgからの5432番のみ許可
#   cost-csv-secretsmanager-endpoint-sg : Secrets Manager等のInterfaceエンドポイント用。lambda-sgからの443番のみ許可

# 【理解する価値あり：ステートフル（stateful）】
# lambda-sgにはインバウンドのルールが1つも無い。それでも通信が成立するのは、SGが
# 「行きを許可したら、その戻りは自動的に許可される」という仕組み（ステートフル）を
# 持っているため。LambdaがSecrets Manager等に話しかける通信は、下のegress（アウトバウンド）
# の全許可で外に出て行く。相手からの返事は「さっき許可して出て行った通信の戻りだ」と
# AWSが自動判定し、インバウンドのルールが無くても戻ってくる。だからlambda-sgは
# インバウンドが空でも成立する（＝Lambda自身への直接の着信を許可する必要が無いだけで、
# Lambdaが自分から話しかけた分の返事は別枠で通る）。
resource "aws_security_group" "lambda" {
  name   = "${var.project_name}-lambda-sg"
  vpc_id = aws_vpc.main.id

  # 【ハマりやすい点】Terraformでegressブロックを1つも書かないと、AWSがSG作成時に
  # 自動で付けてくれるはずの「デフォルトの全許可アウトバウンド」を、Terraformが
  # 「宣言されていない＝要らないルール」と判断して消してしまう。console作成時のデフォルトを
  # そのまま維持したい場合は、その内容（0.0.0.0/0・全ポート許可）を自分で明示的に書く必要がある。
  egress {
    from_port   = 0
    to_port     = 0
    # 「すべてのプロトコル」を意味するAWSの特殊値。TCP・UDP・ICMPなど全部を含む。
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-lambda-sg"
  }
}

# 【理解する価値あり：送信元にSGを指定する仕組み】
# 下のingressの`security_groups = [aws_security_group.lambda.id]`は、
# 「IPアドレスではなく、lambda-sgが付いているENIからの通信だけを許可する」という指定。
# IPで許可リストを作ると、LambdaのENIが再作成されてプライベートIPが変わるたびに
# ルールの書き直しが必要になる。SGを送信元に指定すれば、AWSが通信の瞬間に
# 「この送信元には今lambda-sgが付いているか」を動的に確認するだけなので、
# IPが変わってもルールを書き直す必要がない。
resource "aws_security_group" "db" {
  name   = "${var.project_name}-db-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-db-sg"
  }
}

# db-sgと同じ考え方で、443番（HTTPS）だけをlambda-sgから許可する。
# このSGはレイヤーCで作るSecrets Manager用のInterfaceエンドポイントに使うが、
# ECR API・ECR Docker・CloudWatch LogsのInterfaceエンドポイントも同じ443番の通信のため、
# 新しくSGを増やさずこれを使い回す（vpc_endpoints.tf参照）。
resource "aws_security_group" "secretsmanager_endpoint" {
  name   = "${var.project_name}-secretsmanager-endpoint-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-secretsmanager-endpoint-sg"
  }
}
