#!/usr/bin/env bash
# バックフィル用Dockerイメージをビルドし、ECRにpushする（terraform applyでECRリポジトリを
# 作成した後に実行する。イメージのビルド・pushはbuild.shと同じ理由でTerraformの管轄外）。
set -euo pipefail

cd "$(dirname "$0")/.."

REGION="${AWS_DEFAULT_REGION:-ap-northeast-1}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REPO="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/cost-csv-backfill"

aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

docker build --platform linux/amd64 -f fargate_backfill/Dockerfile -t "$REPO:latest" .
docker push "$REPO:latest"
