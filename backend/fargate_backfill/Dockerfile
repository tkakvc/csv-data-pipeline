# Fargateで動かすバックフィルタスク（⑧）のイメージを作るための設計図（Dockerfile）。
# Dockerfileは「まっさらな環境から、このアプリを動かせる状態を作るまでの手順書」。
# 上から順に1行ずつ実行され、実行結果が「イメージ」という1つの塊（アプリ本体＋実行に必要なもの一式）になる。

# ビルドコンテキストは backend/ ディレクトリを指定すること
# （「ビルドコンテキスト」＝ COPY 命令がファイルを探しに行く基準のフォルダ。
#   下の COPY requirements.txt などは、backend/requirements.txt を指している）
# 例: docker build -f fargate_backfill/Dockerfile -t backfill-task backend/

# ①土台となる環境を指定する。
# 「python:3.12-slim」は、Python 3.12がすでにインストール済みの、軽量版Linux環境
# （Docker Hubという場所に公開されている、他の人が作った既製のイメージを借りてきている）。
FROM python:3.12-slim

# ②これ以降のCOPY・RUN・CMDは、コンテナの中の /app というフォルダを基準に実行する、という指定。
# /app フォルダが無ければ自動的に作られる。
WORKDIR /app

# ③backend/requirements.txt（このアプリが必要とするPythonライブラリの一覧）を、
# コンテナの中の今いる場所（/app、WORKDIRで指定した場所）にコピーする。
# 最後の「.」は「WORKDIRの場所（/app）にコピーする」という意味。
COPY requirements.txt .

# ④コンテナの中で pip install を実行し、③でコピーしたrequirements.txtに書かれた
# ライブラリ（boto3・psycopg2など）を実際にインストールする。
# --no-cache-dir は、pipのダウンロードキャッシュを残さずイメージの容量を減らすオプション。
#
# ソースコード（core/・main.py）より先にrequirements.txtだけを先にコピー・インストールしているのには理由がある。
# Dockerは1行ごとに「レイヤー」という単位で結果を保存し、前回と内容が変わっていない行は再実行せず使い回す。
# ソースコードは変更が頻繁だが、依存ライブラリの一覧はあまり変わらないため、
# 先にライブラリだけインストールしておくと、コードだけ直して作り直すときにpip installをやり直さずに済み、
# イメージのビルドが速くなる。
RUN pip install --no-cache-dir -r requirements.txt

# ⑤アプリ本体のソースコードをコピーする。
# core/ は Lambda（backend/lambda_ingest/handler.py 等）とも共有している共通ロジック
# （CSV解析・DB接続・SQL実行）。バックフィル専用のコードではない。
COPY core/ ./core/
# fargate_backfill/main.py（このタスクのエントリーポイント）を /app 直下にコピーする。
COPY fargate_backfill/main.py .

# ⑥このイメージから実際にコンテナを起動したとき、最初に実行されるコマンド。
# 「python main.py」を実行する、という意味（backend/fargate_backfill/main.pyのif __name__ == "__main__": を参照）。
# ECSがこのタスクを起動すると、このCMDが実行されて処理が始まり、main()の処理が終わるとコンテナも終了する
# （Webサーバーのようにずっと起動し続けるものではなく、1回限りの処理として動く）。
CMD ["python", "main.py"]
