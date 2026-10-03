"""⓪ 署名付きURL発行Lambda。

POST /upload-url の実体。
API Gateway（HTTP API）から呼ばれる、Lambdaプロキシ統合形式のハンドラー。
"""

import json
import os
from datetime import datetime, timezone

import boto3

s3 = boto3.client("s3")

BUCKET_NAME = os.environ["UPLOAD_BUCKET_NAME"]
URL_EXPIRES_IN_SECONDS = 300


def handler(event, context):
    """API Gatewayから呼ばれるエントリーポイント。"""
    # JWTの検証はこのLambdaの前段（Lambda Authorizer）で済んでいる。検証済みのsubが
    # event["requestContext"]["authorizer"]["lambda"]に入って渡される。
    sub = event["requestContext"]["authorizer"]["lambda"]["sub"]

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
