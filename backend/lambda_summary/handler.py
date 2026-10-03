"""⑥ 読み取り専用Lambda。

GET /summary の実体。
"""

import json
import re

from core import db, repository

_MONTH_PATTERN = re.compile(r"\d{4}-\d{2}")


def handler(event, context):
    """API Gatewayから呼ばれるエントリーポイント。"""
    # JWTの検証はこのLambdaの前段（Lambda Authorizer）で済んでいる。検証済みのsubが
    # event["requestContext"]["authorizer"]["lambda"]に入って渡される。これにより、
    # RDS接続のためVPC内に置いているこのLambda自身はインターネットに出る必要が無い。
    sub = event["requestContext"]["authorizer"]["lambda"]["sub"]

    query_params = event.get("queryStringParameters") or {}
    month = query_params.get("month")

    if month and not _MONTH_PATTERN.fullmatch(month):
        return _error_response(400, "VALIDATION_ERROR", "monthはYYYY-MM形式で指定してください")

    conn = db.get_connection()
    items = repository.fetch_summary(conn, sub, month)

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"items": items}),
    }


def _error_response(status_code: int, code: str, message: str) -> dict:
    """エラー時のレスポンスを組み立てる。共通のエラー形式に合わせている。"""
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"error": {"code": code, "message": message}}),
    }
