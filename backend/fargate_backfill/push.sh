#!/usr/bin/env bash
# バックフィル用Dockerイメージをビルドし、ECRにpushする。
#
# 【設計思想：これもbuild.shと同じ理由でTerraformの外に置いている】
# Terraformの仕事は「ECRリポジトリという入れ物を用意する」ところまでで、
# その中に入れる実際のイメージを作る・pushするのはビルドツールの仕事
# （backend/build.sh参照）。Fargateはコンテナイメージ方式のため、そもそもLambdaのzipで
# 起きた「MacとLinuxでバイナリが合わない」問題自体が発生しない（Dockerビルドは常に
# コンテナ内部のLinux環境で行われるため）。それでも--platform linux/amd64を明示しているのは、
# Apple SiliconのMacでdocker buildすると、指定しない場合はARM64向けにビルドされてしまい、
# Fargate（実行環境はX86_64が既定）で動かないことがあるため。
set -euo pipefail

cd "$(dirname "$0")/.."

REGION="${AWS_DEFAULT_REGION:-ap-northeast-1}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REPO="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/cost-csv-backfill"

aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

docker build --platform linux/amd64 -f fargate_backfill/Dockerfile -t "$REPO:latest" .
docker push "$REPO:latest"
