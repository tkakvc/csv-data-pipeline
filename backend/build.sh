#!/usr/bin/env bash
# 各Lambda用のデプロイ用ZIPを作る（terraform applyの前に実行する）。
# Dockerでビルドする理由：psycopg2-binaryはC言語部分を含み、ビルドしたマシンのOS向けの
# バイナリしか作れない。Mac上でそのままpip installするとLinux（Lambdaの実行環境）で動かない
# ため、Lambdaの実行環境と同じLinuxベースのコンテナ内でpip installする
# （詳細はmemo/解説/なぜMacでビルドしたLambdaのコードがLinuxで動かなかったか.md）。
set -euo pipefail

cd "$(dirname "$0")"

for name in presign ingest summary authorizer; do
  rm -rf "build/$name" "build/$name.zip"
  mkdir -p "build/$name"

  docker run --rm --platform linux/amd64 --entrypoint /bin/sh \
    -v "$(pwd)":/var/task -w /var/task \
    public.ecr.aws/lambda/python:3.14 \
    -c "pip install -r requirements.txt -t build/$name"

  cp -r core "lambda_$name/handler.py" "build/$name/"

  (cd "build/$name" && zip -rq "../$name.zip" . -x '*.pyc' -x '__pycache__/*')

  echo "built build/$name.zip"
done
