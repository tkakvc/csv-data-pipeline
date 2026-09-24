"""raw_expenses / summary_expenses / upload_audit_log へのSQL実行関数群。

- 値は必ずプレースホルダ（%s）で渡す。文字列連結でSQLを組み立てない。
- テーブル名だけは環境変数（デプロイ設定）から来るため通常のプレースホルダにできないが、
  攻撃者が制御できるCSVの中身とは別物であり、psycopg2.sql.Identifier() で安全にエスケープする。
"""

from __future__ import annotations

import os
from datetime import date

from psycopg2 import sql
from psycopg2.extras import execute_values

from core.csv_parser import ExpenseRow

RAW_TABLE = os.environ.get("RAW_TABLE_NAME", "raw_expenses")
SUMMARY_TABLE = os.environ.get("SUMMARY_TABLE_NAME", "summary_expenses")
AUDIT_TABLE = os.environ.get("AUDIT_TABLE_NAME", "upload_audit_log")


def insert_raw_rows(conn, user_sub: str, file_key: str, rows: list[ExpenseRow]) -> None:
    """CSVの各行をそのままraw_expensesにINSERTする。"""
    query = sql.SQL(
        """
        INSERT INTO {table}
            (user_sub, source_file_key, usage_date, department_code, department_name,
             account_category, amount, vendor, description)
        VALUES %s
        """
    ).format(table=sql.Identifier(RAW_TABLE))

    values = [
        (
            user_sub,
            file_key,
            r.usage_date,
            r.department_code,
            r.department_name,
            r.account_category,
            r.amount,
            r.vendor,
            r.description,
        )
        for r in rows
    ]

    with conn.cursor() as cur:
        execute_values(cur, query, values)
    conn.commit()


def upsert_summary(conn, user_sub: str, rows: list[ExpenseRow]) -> None:
    """月・部門・勘定科目ごとに金額を合計し、summary_expensesにUPSERTする。"""
    # 同じ「月・部門コード・勘定科目」の行が複数あれば、Python側で先に合算しておく。
    aggregated: dict[tuple[date, str, str], dict] = {}
    for r in rows:
        usage_month = r.usage_date.replace(day=1)
        key = (usage_month, r.department_code, r.account_category)
        bucket = aggregated.setdefault(key, {"department_name": r.department_name, "total": 0})
        bucket["total"] += r.amount

    # 既に同じ組み合わせの行がDBにあれば、ON CONFLICTで既存値とさらに合算する
    # （＝過去のアップロード分と今回の分が、DB上で最終的に足し合わされる）。
    query = sql.SQL(
        """
        INSERT INTO {table}
            (user_sub, usage_month, department_code, department_name, account_category, total_amount)
        VALUES (%s, %s, %s, %s, %s, %s)
        ON CONFLICT (user_sub, usage_month, department_code, account_category)
        DO UPDATE SET
            total_amount = {table}.total_amount + EXCLUDED.total_amount,
            updated_at   = now()
        """
    ).format(table=sql.Identifier(SUMMARY_TABLE))

    with conn.cursor() as cur:
        for (usage_month, department_code, account_category), agg in aggregated.items():
            cur.execute(
                query,
                (user_sub, usage_month, department_code, agg["department_name"], account_category, agg["total"]),
            )
    conn.commit()


def insert_audit_log(
    conn,
    user_sub: str,
    file_key: str,
    status: str,
    row_count: int | None = None,
    error_message: str | None = None,
) -> None:
    """upload_audit_logに1件記録する。"""
    query = sql.SQL(
        """
        INSERT INTO {table} (user_sub, file_key, row_count, status, error_message)
        VALUES (%s, %s, %s, %s, %s)
        """
    ).format(table=sql.Identifier(AUDIT_TABLE))

    with conn.cursor() as cur:
        cur.execute(query, (user_sub, file_key, row_count, status, error_message))
    conn.commit()


def fetch_summary(conn, user_sub: str, month: str | None = None) -> list[dict]:
    """ログイン中ユーザーの集計結果を取得する（GET /summary の実体）。"""
    select_columns = "usage_month, department_code, department_name, account_category, total_amount"
    order_by = "ORDER BY usage_month DESC, department_code, account_category"

    if month:
        query = sql.SQL(
            f"SELECT {select_columns} FROM {{table}} WHERE user_sub = %s AND usage_month = %s {order_by}"
        ).format(table=sql.Identifier(SUMMARY_TABLE))
        # usage_monthカラムは常に月初日で保存されているため、月初日で検索する
        params = (user_sub, date.fromisoformat(f"{month}-01"))
    else:
        query = sql.SQL(f"SELECT {select_columns} FROM {{table}} WHERE user_sub = %s {order_by}").format(
            table=sql.Identifier(SUMMARY_TABLE)
        )
        params = (user_sub,)

    with conn.cursor() as cur:
        cur.execute(query, params)
        rows = cur.fetchall()

    return [
        {
            "usageMonth": row_usage_month.strftime("%Y-%m"),
            "departmentCode": row_department_code,
            "departmentName": row_department_name,
            "accountCategory": row_account_category,
            "totalAmount": row_total_amount,
        }
        for row_usage_month, row_department_code, row_department_name, row_account_category, row_total_amount in rows
    ]


def fetch_all_user_subs(conn) -> list[str]:
    """rawテーブルに登録されている全ユーザーのsub一覧を返す（バックフィルの対象決定に使う）。"""
    query = sql.SQL("SELECT DISTINCT user_sub FROM {table}").format(table=sql.Identifier(RAW_TABLE))
    with conn.cursor() as cur:
        cur.execute(query)
        return [row[0] for row in cur.fetchall()]


def rebuild_summary_for_user(conn, user_sub: str) -> None:
    """指定ユーザーのsummaryを一度全削除し、rawから作り直す（バックフィル用）。"""
    delete_query = sql.SQL("DELETE FROM {table} WHERE user_sub = %s").format(table=sql.Identifier(SUMMARY_TABLE))

    rebuild_query = sql.SQL(
        """
        INSERT INTO {summary}
            (user_sub, usage_month, department_code, department_name, account_category, total_amount)
        SELECT
            user_sub,
            date_trunc('month', usage_date)::date AS usage_month,
            department_code,
            department_name,
            account_category,
            SUM(amount) AS total_amount
        FROM {raw}
        WHERE user_sub = %s
        GROUP BY user_sub, date_trunc('month', usage_date), department_code, department_name, account_category
        """
    ).format(summary=sql.Identifier(SUMMARY_TABLE), raw=sql.Identifier(RAW_TABLE))

    # commit()は最後に1回だけ呼ぶ。DELETEとINSERTの間の中途半端な状態が外から見えないようにするため。
    with conn.cursor() as cur:
        cur.execute(delete_query, (user_sub,))
        cur.execute(rebuild_query, (user_sub,))
    conn.commit()
