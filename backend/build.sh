#!/usr/bin/env bash

# ============================================================
# LambdaへアップロードするZIPファイルを作るスクリプト
# ============================================================
#
# このプロジェクトには次の3つのLambdaがある。
#
#   presign
#   ingest
#   summary
#
# このスクリプトを実行すると、それぞれについて
#
#   build/presign.zip
#   build/ingest.zip
#   build/summary.zip
#
# を作る。
#
# Terraformは、この完成済みZIPをAWS Lambdaへアップロードする。
#
#
# ■ なぜTerraformの中でZIPを作らないのか
#
# Terraformでは aws_lambda_function の source_code_hash を計算するとき、
# terraform plan の時点でZIPファイルを読む。
#
# 一方、null_resource + local-exec などでZIPを作る処理は
# terraform apply の途中で実行される。
#
# つまり、
#
#   terraform plan
#       ↓
#   ZIPを読みたい
#       ↓
#   しかしZIPはまだ作られていない
#
# という問題が起きる。
#
# そのため役割を分けている。
#
#   このスクリプト → ZIPを作る
#   Terraform       → 完成したZIPをAWSへアップロードする
#
#
# ■ なぜpip installをMac上ではなくDockerの中で実行するのか
#
# LambdaはLinux上で動く。
#
# Pythonライブラリの中には、OSやCPUに依存するファイルを含むものがある。
# このプロジェクトで使っている psycopg2-binary もその一つ。
#
# Mac上でpip installするとMac用のファイルが入る可能性があるため、
# それをLambdaへ持っていくと動かないことがある。
#
# そこで、
#
#   Mac
#    ↓
#   DockerでLinux環境を起動
#    ↓
#   そのLinux環境でpip install
#    ↓
#   Lambda用ZIPを作る
#
# という流れにしている。
#
# ============================================================


# ------------------------------------------------------------
# エラーが起きた状態で処理を続けないための設定
# ------------------------------------------------------------

# -e
#   途中のコマンドが失敗したら、このスクリプトもそこで終了する。
#
# -u
#   定義されていない変数を使ったらエラーにする。
#
# -o pipefail
#   「command1 | command2」のような処理で、
#   command1が失敗した場合もスクリプトを失敗扱いにする。
set -euo pipefail


# ------------------------------------------------------------
# backend/ ディレクトリへ移動
# ------------------------------------------------------------

# $0
#   このスクリプト自身のパス
#
# dirname "$0"
#   そのパスからファイル名を除き、
#   スクリプトが置かれているディレクトリを取得する。
#
# たとえば
#
#   /Users/example/project/backend/build.sh
#
# なら
#
#   /Users/example/project/backend
#
# が取得される。
#
# その場所へcdすることで、
# このスクリプトをどのディレクトリから実行しても
# backend/ を基準として処理できる。
cd "$(dirname "$0")"


# ------------------------------------------------------------
# 4つのLambdaを順番にビルドする
# ------------------------------------------------------------

# 1回目: name=presign
# 2回目: name=ingest
# 3回目: name=summary
# 4回目: name=authorizer
for name in presign ingest summary authorizer; do

  # ----------------------------------------------------------
  # 1. 前回作ったファイルを削除
  # ----------------------------------------------------------

  # たとえば name=presign の場合、
  #
  #   build/presign/
  #   build/presign.zip
  #
  # を削除する。
  #
  # 古いライブラリやPythonファイルが残った状態で
  # 新しいZIPを作ってしまうのを防ぐため。
  rm -rf "build/$name" "build/$name.zip"


  # ----------------------------------------------------------
  # 2. ZIPに入れるファイルを集める作業用フォルダを作る
  # ----------------------------------------------------------

  # name=presign なら
  #
  #   build/presign/
  #
  # を作る。
  mkdir -p "build/$name"


  # ----------------------------------------------------------
  # 3. PythonライブラリをLinux環境でインストールする
  # ----------------------------------------------------------
  #
  # ここがこのスクリプトで一番重要な部分。
  #
  # やりたいこと自体は単純で、
  #
  #   pip install -r requirements.txt -t build/presign
  #
  # を「MacではなくLinux上で実行する」だけ。
  #
  # そのLinux環境を一時的に用意するためにDockerを使っている。
  #
  #
  # イメージすると、
  #
  # Mac
  #
  #   backend/
  #   ├─ requirements.txt
  #   ├─ core/
  #   ├─ lambda_presign/
  #   └─ build/
  #
  #          ↓ backend/をDockerから見えるようにする
  #
  # Docker（Linux）
  #
  #   /var/task/
  #   ├─ requirements.txt
  #   ├─ core/
  #   ├─ lambda_presign/
  #   └─ build/
  #
  # Docker内の /var/task は、
  # Mac側の backend/ と同じファイルを見ている。
  #
  #
  # 各オプションの意味：
  #
  # --rm
  #   コマンド実行後、この一時的なDockerコンテナを削除する。
  #
  # --platform linux/amd64
  #   Linuxのamd64（x86_64）環境として実行する。
  #
  # --entrypoint /bin/sh
  #   Lambda用Dockerイメージ本来の起動方法を使わず、
  #   普通のLinuxシェルを起動する。
  #
  # -v "$(pwd)":/var/task
  #   Mac側の現在のディレクトリ（backend/）を、
  #   Docker内の /var/task として見えるようにする。
  #
  #   そのためDocker内で
  #
  #     build/presign/
  #
  #   にファイルを書くと、
  #   Mac側の build/presign/ にもそのファイルが作られる。
  #
  # -w /var/task
  #   Docker内での現在位置を /var/task にする。
  #
  # public.ecr.aws/lambda/python:3.14
  #   AWSが提供しているLambda向けPython 3.14のDockerイメージ。
  #
  # -c "..."
  #   /bin/sh に、この文字列のコマンドを実行させる。
  #
  # pip install -r requirements.txt
  #   requirements.txt に書かれたライブラリをインストールする。
  #
  # -t build/$name
  #   通常のPython環境へインストールするのではなく、
  #   build/presign/ などの指定フォルダへ直接入れる。
  #
  # 結果として、
  #
  #   build/presign/
  #   ├─ psycopg2/
  #   ├─ その他ライブラリ...
  #
  # のようになる。
  docker run --rm --platform linux/amd64 --entrypoint /bin/sh \
    -v "$(pwd)":/var/task \
    -w /var/task \
    public.ecr.aws/lambda/python:3.14 \
    -c "pip install -r requirements.txt -t build/$name"


  # ----------------------------------------------------------
  # 4. 自分たちが書いたPythonコードも作業フォルダへ入れる
  # ----------------------------------------------------------
  #
  # pip installで入れたのは外部ライブラリだけなので、
  # Lambda自身のコードも追加する。
  #
  # name=presignなら、
  #
  #   core/
  #   lambda_presign/handler.py
  #
  # を
  #
  #   build/presign/
  #
  # へコピーする。
  #
  # コピー後はおおよそ次の状態になる。
  #
  # build/presign/
  # ├─ handler.py
  # ├─ core/
  # ├─ psycopg2/
  # └─ その他requirements.txtのライブラリ...
  #
  cp -r core "lambda_$name/handler.py" "build/$name/"


  # ----------------------------------------------------------
  # 5. 全部まとめてZIPにする
  # ----------------------------------------------------------
  #
  # name=presignなら、
  #
  #   build/presign/
  #
  # の中へ一時的に移動して、
  # その中身全部を
  #
  #   build/presign.zip
  #
  # にする。
  #
  # なぜ build/presign 自体ではなく「その中身」をZIPにするのかというと、
  # LambdaではZIPを展開した直下に handler.py が必要だから。
  #
  # 正しい：
  #
  #   presign.zip
  #   ├─ handler.py
  #   ├─ core/
  #   └─ psycopg2/
  #
  # 間違い：
  #
  #   presign.zip
  #   └─ presign/
  #       └─ handler.py
  #
  #
  # ( ... )
  #   この括弧の中だけ別のシェルとして実行する。
  #   そのため、中でcdしても処理後は元のbackend/に戻る。
  #
  # zip -r
  #   フォルダも含めて再帰的にZIP化する。
  #
  # -q
  #   ZIP作成中の細かいログを表示しない。
  #
  # -x '*.pyc' -x '__pycache__/*'
  #   Pythonが自動生成するキャッシュファイルはZIPから除外する。
  #
  (cd "build/$name" && \
    zip -rq "../$name.zip" . \
      -x '*.pyc' \
      -x '__pycache__/*')


  # ----------------------------------------------------------
  # 6. 完成したことを表示
  # ----------------------------------------------------------

  # name=presignなら
  #
  #   built build/presign.zip
  #
  # と表示される。
  echo "built build/$name.zip"

done