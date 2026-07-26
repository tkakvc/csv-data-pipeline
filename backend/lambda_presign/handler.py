"""⓪ 署名付きURL発行Lambda。

POST /upload-url の実体。
API Gateway（HTTP API）から呼ばれる、Lambdaプロキシ統合形式のハンドラー。
"""

import json
import os
from datetime import datetime, timezone

import boto3

from core.auth import extract_bearer_token, verify_google_id_token

s3 = boto3.client("s3")

BUCKET_NAME = os.environ["UPLOAD_BUCKET_NAME"]
GOOGLE_OAUTH_CLIENT_ID = os.environ["GOOGLE_OAUTH_CLIENT_ID"]
URL_EXPIRES_IN_SECONDS = 300


def handler(event, context):
    """API Gatewayから呼ばれるエントリーポイント（一番最初に実行される関数）。
    eventにはHTTPリクエストの情報（ヘッダー・パスなど）がまとめて入っている。
    """
    # ① JWTを取り出して検証する。失敗したら401エラーを返す。
    #    try/exceptは「tryの中でエラーが起きたら、exceptの中の処理に切り替える」という構文。
    try:
        token = extract_bearer_token(event.get("headers", {}))
        claims = verify_google_id_token(token, GOOGLE_OAUTH_CLIENT_ID)
    except Exception:
        return _error_response(401, "UNAUTHORIZED", "有効な認証トークンがありません")

    sub = claims["sub"]  # 検証済みJWTから、ユーザーを一意に識別するsubクレームを取り出す

    # ② 保存先パスはクライアントの申告値を使わず、検証済みのsubからサーバー側で組み立てる
    #    （他人のパスに書き込めてしまうことを防ぐため）。
    #    f"..." はf文字列という書き方で、{}の中に変数の値をそのまま埋め込める。
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    key = f"uploads/{sub}/{timestamp}_costs.csv"

    # ③ S3への署名付きPUT URL（一時的な書き込み許可証）を発行する
    url = s3.generate_presigned_url(
        "put_object",
        Params={"Bucket": BUCKET_NAME, "Key": key, "ContentType": "text/csv"},
        ExpiresIn=URL_EXPIRES_IN_SECONDS,
    )

    # ④ API Gatewayへのレスポンスは、この形の辞書で返す決まりになっている
    #    （Lambdaプロキシ統合という方式のルール。statusCode/headers/bodyを持つ）。
    #    json.dumps()はPythonの辞書をJSON文字列に変換する関数。
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"url": url, "key": key, "expiresIn": URL_EXPIRES_IN_SECONDS}),
    }


def _error_response(status_code: int, code: str, message: str) -> dict:
    """エラー時のレスポンスを組み立てる。共通のエラー形式に合わせている。"""
    # 関数名の先頭の _ は「このモジュールの外からは使わない、内部専用の関数」という慣習的な印
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"error": {"code": code, "message": message}}),
    }
