# RDSとその認証情報（memo/spec/terraform.mdの「認証情報管理：セルフマネージド」に対応）：
# RDSの「Secrets Managerでマスター認証情報を管理」機能（manage_master_user_password）は使わず、
# パスワードをTerraformで生成してSecrets Managerに自分で保存する。理由は、その機能が作る
# シークレットの中身は`password`のみで、host・port・dbname等の接続情報は別途自分で
# 組み立てる必要があり、既存のバックエンドコード（backend/core/db.py）が期待する
# 「1つのシークレットにhost・port・dbname・username・password全部入り」という形に合わないため

resource "random_password" "db_master" {
  length  = 24
  special = false
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group-private"
  subnet_ids = [aws_subnet.private1.id, aws_subnet.private2.id]

  tags = {
    Name = "${var.project_name}-db-subnet-group-private"
  }
}

resource "aws_db_instance" "main" {
  identifier     = "${var.project_name}-db"
  engine         = "postgres"
  engine_version = "18.3"
  instance_class = "db.t4g.micro"

  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = "cost_csv"
  username = "postgres"
  password = random_password.db_master.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false

  backup_retention_period = 1
  skip_final_snapshot     = true

  tags = {
    Name = "${var.project_name}-db"
  }
}

# backend/core/db.pyがそのままSecretsManagerのJSONを読める形（username/password/engine/host/port/dbname/
# dbInstanceIdentifier）で保存する
resource "aws_secretsmanager_secret" "db_credentials" {
  name = "${var.project_name}-db-credentials"

  tags = {
    Name = "${var.project_name}-db-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username             = aws_db_instance.main.username
    password             = random_password.db_master.result
    engine               = "postgres"
    host                 = aws_db_instance.main.address
    port                 = aws_db_instance.main.port
    dbname               = aws_db_instance.main.db_name
    dbInstanceIdentifier = aws_db_instance.main.identifier
  })
}
