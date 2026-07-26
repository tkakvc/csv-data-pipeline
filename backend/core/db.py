"""DB接続の管理。

RDSの認証情報はSecrets Manager経由で取得し、環境変数やコードに平文で埋め込まない。
"""

import json
import os

import boto3
import psycopg2

# boto3.client("secretsmanager") は「AWSのSecrets Manager（秘密情報の保管庫）を操作するための道具」を作る処理。
_secrets_client = boto3.client("secretsmanager")

# Lambdaは同じ実行環境（ウォームスタート）が使い回されることがあるため、
# モジュールレベルの変数にコネクションを保持し、呼び出しごとに接続し直さないようにする。
# モジュールレベル＝関数の外に書かれた変数のこと。このファイルがimportされている間、値を保持し続ける。
_connection = None


def get_connection():
    """PostgreSQLへのコネクションを返す。既存の有効なコネクションがあれば使い回す。"""
    # global _connection：この関数の中で_connectionに代入すると、
    # 関数だけのローカル変数ではなく、ファイル冒頭で定義したモジュールレベルの変数を書き換える、という宣言。
    # これを書かないと、関数の中の_connectionは別物の新しい変数として扱われてしまう。
    global _connection

    # すでに接続済みで、かつ閉じられていない（closed == 0）なら、それをそのまま使い回す。
    # → 毎回DBに接続し直すのは時間がかかるため、使い回せるときは使い回して高速化している。
    if _connection is not None and _connection.closed == 0:
        return _connection

    # 環境変数からSecrets ManagerのARN（そのシークレットを一意に指し示す識別子）を取得
    secret_arn = os.environ["DB_SECRET_ARN"]
    # Secrets Managerから実際の接続情報（ホスト名・ユーザー名・パスワードなど）をJSON文字列として取得し、
    # json.loads()でPythonの辞書に変換する
    secret = json.loads(_secrets_client.get_secret_value(SecretId=secret_arn)["SecretString"])

    # 取得した接続情報を使ってPostgreSQLに実際に接続する
    _connection = psycopg2.connect(
        host=secret["host"],
        port=secret.get("port", 5432),  # portがsecretに無ければデフォルトの5432番を使う
        dbname=secret["dbname"],
        user=secret["username"],
        password=secret["password"],
        connect_timeout=5,  # 5秒以内に繋がらなければタイムアウトさせる
    )
    return _connection
