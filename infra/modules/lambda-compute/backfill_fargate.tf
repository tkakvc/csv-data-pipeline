# ⑧バックフィルFargateタスク（docs/api.md 4章）。
#
# 【設計思想：なぜaws_ecs_serviceを作らないのか】
# ECSには「常時起動して自動で再起動し続けるコンテナ」を作る aws_ecs_service という
# リソースがあるが、ここでは使わない。バックフィルは「集計ロジックを直した後などに、
# 気づいた時に手で1回実行する」処理であり、常時起動しておく理由が無い
# （常時起動すればFargateの課金もその分発生し続ける）。だから作るのは
# 「どう動かすかの設計図」であるタスク定義（aws_ecs_task_definition）までで、
# 実際の起動は`aws ecs run-task`をその都度手で叩く運用にしている（docs/api.md 4章参照）。

resource "aws_ecr_repository" "backfill" {
  name = "${var.project_name}-backfill"
}

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"
}

# 【理解する価値あり：クラスタとキャパシティプロバイダは別リソース】
# 「ECSクラスタ」自体は名前space（タスクをグルーピングする箱）でしかなく、
# 「Fargateで動かせるようにする」設定は別のリソース（aws_ecs_cluster_capacity_providers）
# に分かれている。FARGATE_SPOTも一覧に加えているのは、将来コストを抑えたい場合に
# 選べる余地を残しておくためで、今回は実際にはFARGATE（オンデマンド）を使っている
# （run-task時に--capacity-provider-strategyを指定しない限りデフォルトはFARGATE）。
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
}

# 【理解する価値あり：Lambdaと同じ信頼ポリシーだが、principalが違う】
# presign_lambda.tf等の assume_role_policy と書き方は同じだが、identifiersが
# "lambda.amazonaws.com"ではなく"ecs-tasks.amazonaws.com"になっている。
# 「誰がこのロールを装ってよいか」はサービスごとに別物で、ECSのタスク（実行ロール・
# タスクロールの両方）を動かすのはECSタスクの実行エンジン（ecs-tasks.amazonaws.com）
# なので、これを許可しないとタスク自体が起動できない。1つのdata定義を
# 実行ロール・タスクロールの両方（下のaws_iam_role.ecs_task_execution・
# aws_iam_role.backfill_taskの2箇所）で使い回しているのは、
# 「誰が装ってよいか」の条件自体は完全に同じで、違うのは「装った後に何ができるか」
# （付けるポリシーの中身）だけだから。
data "aws_iam_policy_document" "ecs_tasks_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# 【設計思想：なぜ既存の"ecsTaskExecutionRole"を使い回さないのか】
# AWSコンソールでECSタスクを作ると、"ecsTaskExecutionRole"という汎用的な名前の
# 実行ロールが（無ければ）自動生成される。このAWSアカウントには既に career-support-app側の
# ECSタスクが使っているものが存在しており、名前が汎用的すぎて「本当にこのプロジェクト専用か」
# を名前だけでは判断できない。他プロジェクトと共有される可能性のあるリソースをTerraformで
# 管理（削除・変更）対象にすると、そちら側に影響が及ぶリスクがあるため、
# このプロジェクト専用の名前を持つ実行ロールを別途新規に作る。
#
# 【実行ロールとタスクロールの違い】
# 実行ロール（execution role）＝ECSエージェント自身が「ECRからイメージをpullする」
# 「CloudWatch Logsにログを送る」ために使う権限。
# タスクロール（task role）＝コンテナの中で動くアプリ本体（main.py）が使う権限。
# 「タスクを起動する仕組み」と「起動後に中で動くコード」で、必要な権限の種類が全く違うため、
# AWSの設計として最初から2つのロールに分かれている。
resource "aws_iam_role" "ecs_task_execution" {
  name               = "${var.project_name}-ecs-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "backfill_task" {
  name               = "${var.project_name}-backfill-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json
}

# main.pyが実際にやるのは「DBのシークレットを1個読む」だけなので、権限もそこにちょうど絞る
# （presign・summary・ingest Lambdaと同じ考え方）
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

# 【理解する価値あり：container_definitionsはjsonencode()で1つの巨大な文字列にする】
# aws_lambda_functionのenvironment{}のようなHCL専用の入れ子ブロックではなく、
# ECSタスク定義のコンテナ設定はAWS側では元々JSON形式の1つの塊として渡す仕様になっている。
# そのためs3.tfのバケットポリシーと同じ考え方で、HCLで書いてjsonencode()でJSON化している。
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
      # 対象ユーザーを絞るTARGET_USER_SUBはここに書かない。`aws ecs run-task`実行時に
      # --overridesで都度渡す想定の値（省略時は全ユーザー対象）で、タスク定義に
      # 固定するとユーザーごとに毎回タスク定義を書き換える羽目になるため（docs/api.md 4章参照）
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
