"""DB接続の管理。

RDSの認証情報はSecrets Manager経由で取得し、環境変数やコードに平文で埋め込まない。
"""

import json
import os

import boto3
import psycopg2

_secrets_client = boto3.client("secretsmanager")

# Lambdaは同じ実行環境（ウォームスタート）が使い回されることがあるため、
# モジュールレベルの変数にコネクションを保持し、呼び出しごとに接続し直さないようにする。
_connection = None


def get_connection():
    """PostgreSQLへのコネクションを返す。既存の有効なコネクションがあれば使い回す。"""
    global _connection

    if _connection is not None and _connection.closed == 0:
        return _connection

    secret_arn = os.environ["DB_SECRET_ARN"]
    secret = json.loads(_secrets_client.get_secret_value(SecretId=secret_arn)["SecretString"])

    _connection = psycopg2.connect(
        host=secret["host"],
        port=secret.get("port", 5432),
        dbname=secret["dbname"],
        user=secret["username"],
        password=secret["password"],
        connect_timeout=5,
    )
    return _connection
