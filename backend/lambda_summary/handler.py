"""⑥ 読み取り専用Lambda。

GET /summary の実体。
"""

import json
import os
import re

from core import db, repository
from core.auth import extract_bearer_token, verify_google_id_token

GOOGLE_OAUTH_CLIENT_ID = os.environ["GOOGLE_OAUTH_CLIENT_ID"]

# "2026-07" のようなYYYY-MM形式かどうかをチェックするための正規表現パターン。
# \d{4} は数字4桁、\d{2} は数字2桁、という意味。
_MONTH_PATTERN = re.compile(r"\d{4}-\d{2}")


def handler(event, context):
    """API Gatewayから呼ばれるエントリーポイント。"""
    # ① JWTを検証する。失敗したら401エラー。
    try:
        token = extract_bearer_token(event.get("headers", {}))
        claims = verify_google_id_token(token, GOOGLE_OAUTH_CLIENT_ID)
    except Exception:
        return _error_response(401, "UNAUTHORIZED", "有効な認証トークンがありません")

    sub = claims["sub"]

    # ② クエリパラメータ（URLの ?month=2026-07 の部分）からmonthを取り出す
    query_params = event.get("queryStringParameters") or {}
    month = query_params.get("month")

    # ③ monthが指定されているのにYYYY-MM形式でなければ400エラー
    #    fullmatch()は「文字列全体がこのパターンに完全に一致するか」を調べるメソッド
    if month and not _MONTH_PATTERN.fullmatch(month):
        return _error_response(400, "VALIDATION_ERROR", "monthはYYYY-MM形式で指定してください")

    # ④ DBから、このユーザー（sub）自身の集計結果だけを取得する
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
