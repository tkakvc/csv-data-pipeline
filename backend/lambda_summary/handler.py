"""⑥ 読み取り専用Lambda。

GET /summary の実体。
"""

import json
import os
import re

from core import db, repository
from core.auth import extract_bearer_token, verify_google_id_token

GOOGLE_OAUTH_CLIENT_ID = os.environ["GOOGLE_OAUTH_CLIENT_ID"]

_MONTH_PATTERN = re.compile(r"\d{4}-\d{2}")


def handler(event, context):
    """API Gatewayから呼ばれるエントリーポイント。"""
    try:
        token = extract_bearer_token(event.get("headers", {}))
        claims = verify_google_id_token(token, GOOGLE_OAUTH_CLIENT_ID)
    except Exception:
        return _error_response(401, "UNAUTHORIZED", "有効な認証トークンがありません")

    sub = claims["sub"]

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
