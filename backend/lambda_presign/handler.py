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
    """API Gatewayから呼ばれるエントリーポイント。"""
    try:
        token = extract_bearer_token(event.get("headers", {}))
        claims = verify_google_id_token(token, GOOGLE_OAUTH_CLIENT_ID)
    except Exception:
        return _error_response(401, "UNAUTHORIZED", "有効な認証トークンがありません")

    sub = claims["sub"]

    # 保存先パスはクライアントの申告値を使わず、検証済みのsubからサーバー側で組み立てる
    # （他人のパスに書き込めてしまうことを防ぐため）。
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    key = f"uploads/{sub}/{timestamp}_costs.csv"

    url = s3.generate_presigned_url(
        "put_object",
        Params={"Bucket": BUCKET_NAME, "Key": key, "ContentType": "text/csv"},
        ExpiresIn=URL_EXPIRES_IN_SECONDS,
    )

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"url": url, "key": key, "expiresIn": URL_EXPIRES_IN_SECONDS}),
    }


def _error_response(status_code: int, code: str, message: str) -> dict:
    """エラー時のレスポンスを組み立てる。共通のエラー形式に合わせている。"""
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"error": {"code": code, "message": message}}),
    }
