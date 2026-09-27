#!/usr/bin/env bash
# 各Lambda用のデプロイ用ZIPを作る（terraform applyの前に実行する）。
#
# 【設計思想：なぜTerraformの中でZIPを作らないのか】
# 最初は null_resource + local-exec でビルドまでTerraformの中に押し込む案も考えたが、
# aws_lambda_functionのsource_code_hashは terraform plan の時点でファイルの中身を
# 読みに行くのに対し、ビルド自体（local-exec）は terraform apply の時点でしか走らない。
# つまり「plan時点ではまだ存在しないファイルを読もうとする」という順番の矛盾が起きる。
# だから「ビルドはTerraformの外の仕事」と割り切り、このスクリプト1本に専念させ、
# Terraformは「出来上がったzipをアップロードするだけ」に役割を絞っている
# （memo/解説/なぜMacでビルドしたLambdaのコードがLinuxで動かなかったか.md 疑問5参照）。
#
# 【なぜDockerでビルドするのか】
# psycopg2-binaryはC言語部分を含み、ビルドしたマシンのOS向けのバイナリしか作れない。
# Mac上でそのままpip installするとLinux（Lambdaの実行環境）で動かない
# （実際にこのプロジェクトで起きた`Runtime.ImportModuleError`の原因。詳細は上記メモ参照）。
# Lambdaの実行環境と同じLinuxベースのコンテナ内でpip installすれば、
# 特別なオプションを覚えなくても自動的にLinux向けのファイルができる。
set -euo pipefail

cd "$(dirname "$0")"

for name in presign ingest summary; do
  rm -rf "build/$name" "build/$name.zip"
  mkdir -p "build/$name"

  # --entrypoint /bin/sh -c "...": このLambda公式イメージは通常「渡した引数をハンドラ名として
  # 実行する」独自のentrypointを持っているため、それを上書きして普通のシェルとして使っている
  docker run --rm --platform linux/amd64 --entrypoint /bin/sh \
    -v "$(pwd)":/var/task -w /var/task \
    public.ecr.aws/lambda/python:3.14 \
    -c "pip install -r requirements.txt -t build/$name"

  cp -r core "lambda_$name/handler.py" "build/$name/"

  (cd "build/$name" && zip -rq "../$name.zip" . -x '*.pyc' -x '__pycache__/*')

  echo "built build/$name.zip"
done
