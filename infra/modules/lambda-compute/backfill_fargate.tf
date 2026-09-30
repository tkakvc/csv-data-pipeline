# ⑧バックフィルFargateタスク（docs/api.md 4章）。ECSサービスは作らない：常時起動する必要が
# 無く、`aws ecs run-task`で手動起動するだけの構成（EventBridge等の起動トリガーも無し）。

resource "aws_ecr_repository" "backfill" {
  name = "${var.project_name}-backfill"
}

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
}

data "aws_iam_policy_document" "ecs_tasks_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# 実行ロール（execution role）：ECRからイメージをpull・CloudWatch Logsに書き込むための、
# ECSエージェント自身が使う権限。既存の汎用ロール（ecsTaskExecutionRole）は
# career-support-app側と共用の可能性があるため使い回さず、専用のロールを作る。
resource "aws_iam_role" "ecs_task_execution" {
  name               = "${var.project_name}-ecs-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# タスクロール（task role）：コンテナの中で実行するコード（main.py）自身が使う権限。
# 実行ロールとは別物：実行ロールは「タスクを起動する仕組み」の権限、タスクロールは
# 「起動後、中で動くアプリが呼ぶAWS API」の権限
resource "aws_iam_role" "backfill_task" {
  name               = "${var.project_name}-backfill-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json
}

resource "aws_iam_role_policy" "backfill_task" {
  name = "${var.project_name}-backfill-task-policy"
  role = aws_iam_role.backfill_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = var.db_secret_arn
      }
    ]
  })
}

resource "aws_ecs_task_definition" "backfill" {
  family                   = "backfill-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.backfill_task.arn

  container_definitions = jsonencode([
    {
      name  = "${var.project_name}-backfill"
      image = "${aws_ecr_repository.backfill.repository_url}:latest"
      # DB_SECRET_ARNは固定の環境変数。対象ユーザーを絞るTARGET_USER_SUBは
      # `aws ecs run-task`実行時に--overridesで都度渡す想定のため、ここには書かない
      # （docs/api.md 4章の実行コマンド例参照）
      environment = [
        { name = "DB_SECRET_ARN", value = var.db_secret_arn }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/backfill-task"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
          "awslogs-create-group"  = "true"
        }
      }
    }
  ])
}
