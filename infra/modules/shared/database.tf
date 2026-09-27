# 【前提：RDSの認証情報管理には2種類ある】
# RDSには「Secrets Managerでマスター認証情報を管理」という機能（Terraformでは
# manage_master_user_password = true）があり、有効にするとAWSがパスワードを自動生成し
# Secrets Managerに保存までしてくれる。ただしその場合にAWSが作るシークレットの中身は
# パスワードのみで、host・port・dbname等の接続情報は別途自分で組み立てる必要がある。
#
# 一方、既存のバックエンドコード（backend/core/db.py）は「1つのシークレットに
# host・port・dbname・username・password全部入り」という前提で書かれている
# （これはAWSコンソールで手動作成した際の形式をそのまま踏襲している）。
# コードを変えずに済ませるため、ここではAWS任せの機能を使わず、パスワードの生成から
# シークレットの中身の組み立てまで全部自分でTerraformに書く（認証情報管理はセルフマネージド）。

# 【理解する価値あり：randomプロバイダ】
# awsプロバイダはAWSリソースを作るためのプラグインだが、パスワード生成はAWSの操作では
# ないので別のプラグイン（hashicorp/random）が必要。variables.tf・envs/dev/providers.tf
# にrequired_providersとしてrandomを追加している。
resource "random_password" "db_master" {
  length  = 24
  # 特殊記号を含めない。RDSのパスワードには使える文字種に制限があり、DB接続文字列や
  # Secrets ManagerのJSON文字列に含めた際にエスケープが必要な文字（"/"や"@"等）を
  # 避けたいので、素直に英数字だけにしている。
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
  # random_password.db_master.resultは実際のパスワード文字列そのもの。
  # 生成した値をここと、下のSecrets Managerのシークレット内容の両方に使うことで、
  # 「RDSに設定したパスワード」と「Secrets Managerに保存したパスワード」が
  # 必ず一致する状態を保証している（手打ちで2箇所に書くと食い違う事故が起きやすい）。
  password = random_password.db_master.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false

  backup_retention_period = 1
  # skip_final_snapshot：terraform destroy時に最終スナップショットを作らず即削除する設定。
  # 本番運用ならfalseにして残すべきだが、このプロジェクトは学習用でデータもサンプルCSVのみ
  # のため、destroy時にスナップショット名の指定を毎回求められる手間を避けている。
  skip_final_snapshot = true

  tags = {
    Name = "${var.project_name}-db"
  }
}

# backend/core/db.pyがそのままSecrets ManagerのJSONを読める形（username/password/engine/host/
# port/dbname/dbInstanceIdentifier）で保存する。keyの名前はコード側の`secret["host"]`等の
# 参照と完全に一致させる必要がある（Terraform側で自由に決めているわけではない）。
resource "aws_secretsmanager_secret" "db_credentials" {
  name = "${var.project_name}-db-credentials"

  tags = {
    Name = "${var.project_name}-db-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  # 【理解する価値あり】jsonencode()：Terraformのmap（{ key = value, ... }）を
  # JSON文字列に変換する組み込み関数。aws_secretsmanager_secret_versionのsecret_stringは
  # 単なる文字列を要求するため、Pythonのjson.dumps()と同じ役割をここで使っている。
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
