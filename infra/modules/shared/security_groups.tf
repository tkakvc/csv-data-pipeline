# 各SGの役割（docs/network.md 4章参照）：
#   cost-csv-lambda-sg                  : Lambda・Fargateタスクに付与する送信元SG。インバウンドは持たない
#   cost-csv-db-sg                      : RDS用。lambda-sgからの5432番のみ許可
#   cost-csv-secretsmanager-endpoint-sg : Secrets Manager等のInterfaceエンドポイント用。lambda-sgからの443番のみ許可
#
# lambda-sgのインバウンドが空でも通信が成立するのは、SGがステートフルなため
# （行きを許可すれば戻りは自動で通る。docs/network.md 4章参照）。アウトバウンドはいずれも
# コンソール作成時のデフォルト（0.0.0.0/0・全ポート許可）のままなので、ここでも明示的に同じ内容を書いている
# （Terraformはegressブロックを書かないと、AWSが自動付与するデフォルトの全許可egressを消してしまうため）

resource "aws_security_group" "lambda" {
  name   = "${var.project_name}-lambda-sg"
  vpc_id = aws_vpc.main.id

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
