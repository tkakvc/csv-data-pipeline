"""⑥ 読み取り専用Lambda。

GET /summary の実体。
"""

import json
import re

from core import db, repository

# "2026-07" のようなYYYY-MM形式かどうかをチェックするための正規表現パターン。
# \d{4} は数字4桁、\d{2} は数字2桁、という意味。
_MONTH_PATTERN = re.compile(r"\d{4}-\d{2}")


def handler(event, context):
    """API Gatewayから呼ばれるエントリーポイント。"""
    # ① JWTの検証はこのLambdaの前段（Lambda Authorizer）で既に済んでいる。
    #    検証済みのsubだけが、event["requestContext"]["authorizer"]["lambda"]に入って渡される
    #    （lambda_authorizer/handler.py参照）。ここで自分で検証をやり直す必要はない。
    #    これにより、このLambda自身はインターネット（GoogleのJWKS）へ出る必要が無くなる
    #    （VPCの中からインターネットへ出られずタイムアウトしていた問題の解消。docs/architecture.md参照）。
    sub = event["requestContext"]["authorizer"]["lambda"]["sub"]

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
