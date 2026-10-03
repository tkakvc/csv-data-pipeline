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
    """API Gatewayから呼ばれるエントリーポイント（一番最初に実行される関数）。
    eventにはHTTPリクエストの情報（ヘッダー・パスなど）がまとめて入っている。
    """
    # ① JWTの検証はこのLambdaの前段（Lambda Authorizer）で既に済んでいる。
    #    検証済みのsubだけが、event["requestContext"]["authorizer"]["lambda"]に入って渡される
    #    （lambda_authorizer/handler.py参照）。ここで自分で検証をやり直す必要はない。
    sub = event["requestContext"]["authorizer"]["lambda"]["sub"]

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
