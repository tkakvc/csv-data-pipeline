"""④ CSV取込Lambda。

S3のイベント通知から直接呼び出される非同期処理
（EventBridgeは経由しない。LambdaはS3が直接呼び出せる対象なので仲介役が不要なため）。
"""

import logging
from urllib.parse import unquote_plus

import boto3

from core import csv_parser, db, repository

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client("s3")


def handler(event, context):
    """S3がCSVアップロードを検知したときに呼び出されるエントリーポイント。
    eventの中には、アップロードされたS3オブジェクトの情報が"Records"というリストで入っている
    （1回のイベントで複数ファイル分入っている可能性があるため、for文で1件ずつ処理する）。
    """
    logger.info("Received event: %s", event)  # 調査用の一時的なログ
    for record in event["Records"]:
        _process_record(record)


def _process_record(record: dict) -> None:
    """S3イベント1件分（＝アップロードされたファイル1つ分）を処理する。"""
    bucket = record["s3"]["bucket"]["name"]
    # S3イベントのkeyはURLエンコード（例："|"が"%7C"になる）されているのでデコードする
    key = unquote_plus(record["s3"]["object"]["key"])

    sub = _extract_sub_from_key(key)
    conn = db.get_connection()

    # S3から実際のCSVファイルの中身（バイト列）をダウンロードする
    raw_bytes = s3.get_object(Bucket=bucket, Key=key)["Body"].read()

    # ① CSVをパース・検証する。1行でも不正な行があればValidationErrorが飛んでくる
    #    （csv_parser.pyの説明参照。最初に見つかった1件のエラーで処理が止まる）。
    try:
        rows = csv_parser.parse_and_validate(raw_bytes)
    except csv_parser.ValidationError as e:
        # 検証に失敗した場合：失敗ログを残して、DBへの書き込みはせずに終了する
        logger.warning("CSV validation failed for key=%s: %s", key, e)
        repository.insert_audit_log(conn, sub, key, status="failed", error_message=str(e))
        return  # ここで関数を抜ける（以降の成功処理は実行されない）

    # ② 検証に成功した場合：生データの保存→集計テーブルの更新→成功ログの記録、の順に実行する
    repository.insert_raw_rows(conn, sub, key, rows)
    repository.upsert_summary(conn, sub, rows)
    repository.insert_audit_log(conn, sub, key, status="success", row_count=len(rows))

    logger.info("Ingested %d rows from key=%s (user_sub=%s)", len(rows), key, sub)


def _extract_sub_from_key(key: str) -> str:
    """"uploads/{sub}/{filename}" という命名規則からsubを取り出す。"""
    # "uploads/google-oauth2|12345/xxxx.csv" を "/" で分割すると
    # ["uploads", "google-oauth2|12345", "xxxx.csv"] という3つの要素のリストになる
    parts = key.split("/")
    if len(parts) < 3 or parts[0] != "uploads":
        raise ValueError(f"unexpected S3 key format: {key!r}")
    return parts[1]  # 2番目の要素（sub部分）を返す
