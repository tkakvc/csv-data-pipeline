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

# テーブル名は環境変数から取得し、無指定ならデフォルト名を使う
RAW_TABLE = os.environ.get("RAW_TABLE_NAME", "raw_expenses")
SUMMARY_TABLE = os.environ.get("SUMMARY_TABLE_NAME", "summary_expenses")
AUDIT_TABLE = os.environ.get("AUDIT_TABLE_NAME", "upload_audit_log")


def insert_raw_rows(conn, user_sub: str, file_key: str, rows: list[ExpenseRow]) -> None:
    """CSVの各行をそのままraw_expensesにINSERTする。"""
    # sql.SQL(...).format(table=sql.Identifier(RAW_TABLE)) は、
    # 文中の「{table}」の部分をテーブル名に安全に置き換えてSQL文を組み立てる書き方。
    # 通常の文字列連結（f"INSERT INTO {RAW_TABLE} ..."）と違い、
    # テーブル名に危険な文字が入っていた場合も自動でエスケープしてくれる。
    query = sql.SQL(
        """
        INSERT INTO {table}
            (user_sub, source_file_key, usage_date, department_code, department_name,
             account_category, amount, vendor, description)
        VALUES %s
        """
    ).format(table=sql.Identifier(RAW_TABLE))

    # rowsの各要素（ExpenseRow）を、INSERT文に渡せるタプル（値の組）の並びに変換する。
    # これも「リスト内包表記」（csv_parser.pyのparse_and_validateで説明したのと同じ書き方）。
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

    # execute_valuesは「VALUES %s」の部分に、valuesのリストを1回のSQL実行でまとめて差し込んでくれる関数。
    # rowsの件数分だけcur.execute()を繰り返すより高速。
    # "with conn.cursor() as cur:" は、カーソル（SQLを実行するための窓口）を使い終わったら
    # 自動的に後片付け（close）してくれる書き方。
    with conn.cursor() as cur:
        execute_values(cur, query, values)
    conn.commit()  # ここまでの変更をDBに確定させる


def upsert_summary(conn, user_sub: str, rows: list[ExpenseRow]) -> None:
    """月・部門・勘定科目ごとに金額を合計し、summary_expensesにUPSERTする。"""
    # ① まずPython側で、同じ「月・部門コード・勘定科目」の組み合わせごとに金額を合計しておく。
    #    例：今回渡されたCSVの中に (2026-07, SALES, 交通費) の行が2つあれば、ここで先に金額を合算してしまう。
    #    aggregated は {(月, 部門コード, 勘定科目): {"department_name": ..., "total": 合計金額}} という辞書。
    aggregated: dict[tuple[date, str, str], dict] = {}
    for r in rows:
        usage_month = r.usage_date.replace(day=1)  # 日付部分を1日に変えて「月初日」にする
        key = (usage_month, r.department_code, r.account_category)
        # setdefault(key, 初期値) は「keyが辞書に無ければ初期値を入れて、あるものをそのまま返す」という動き。
        bucket = aggregated.setdefault(key, {"department_name": r.department_name, "total": 0})
        bucket["total"] += r.amount

    # ② UPSERT文（ON CONFLICT DO UPDATE SET）を組み立てる。
    #    DBにすでに同じ組み合わせの行がある場合は、DB側でさらに既存値と合算される
    #    （＝過去のアップロード分と今回の分が、DB上で最終的に足し合わされる）。
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

    # ③ ①で作った組み合わせごとに、1回ずつUPSERTを実行する
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
    # row_count・error_messageは呼び出し元が指定しなければNoneのまま渡ってよい（デフォルト引数）
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

    # monthが指定されているかどうかで、WHERE句の条件を出し分けている
    if month:
        query = sql.SQL(
            f"SELECT {select_columns} FROM {{table}} WHERE user_sub = %s AND usage_month = %s {order_by}"
        ).format(table=sql.Identifier(SUMMARY_TABLE))
        # "2026-07" のような文字列に "-01" を足して "2026-07-01" にし、date型に変換する
        # （usage_monthカラムは常に月初日で保存されているため、月初日で検索する必要がある）
        params = (user_sub, date.fromisoformat(f"{month}-01"))
    else:
        query = sql.SQL(f"SELECT {select_columns} FROM {{table}} WHERE user_sub = %s {order_by}").format(
            table=sql.Identifier(SUMMARY_TABLE)
        )
        params = (user_sub,)

    with conn.cursor() as cur:
        cur.execute(query, params)
        rows = cur.fetchall()  # SELECT結果を全部取り出す（タプルのリストになる）

    # DBから取れた行（タプル）を、レスポンスで返すJSON用の辞書（キャメルケースのキー）に変換する。
    # これも「リスト内包表記」で、for文と同じ意味。
    return [
        {
            "usageMonth": row_usage_month.strftime("%Y-%m"),  # date型を "2026-07" のような文字列に変換
            "departmentCode": row_department_code,
            "departmentName": row_department_name,
            "accountCategory": row_account_category,
            "totalAmount": row_total_amount,
        }
        for row_usage_month, row_department_code, row_department_name, row_account_category, row_total_amount in rows
    ]


def fetch_all_user_subs(conn) -> list[str]:
    """rawテーブルに登録されている全ユーザーのsub一覧を返す（バックフィルの対象決定に使う）。"""
    # DISTINCTは「重複を除いて、ユニークな値だけを返す」というSQLの指定
    query = sql.SQL("SELECT DISTINCT user_sub FROM {table}").format(table=sql.Identifier(RAW_TABLE))
    with conn.cursor() as cur:
        cur.execute(query)
        # row[0] は、SELECTで返ってきた1行（タプル）の1列目（user_subだけ）を取り出している
        return [row[0] for row in cur.fetchall()]


def rebuild_summary_for_user(conn, user_sub: str) -> None:
    """指定ユーザーのsummaryを一度全削除し、rawから作り直す（バックフィル用）。"""
    delete_query = sql.SQL("DELETE FROM {table} WHERE user_sub = %s").format(table=sql.Identifier(SUMMARY_TABLE))

    # rawテーブルを月・部門・勘定科目でGROUP BYして合計し直し、summaryに入れ直すSQL
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

    # DELETEとINSERTを同じカーソル・同じコネクションで実行し、最後にまとめてcommit()する。
    # conn.commit()を呼ぶまではDBに変更が確定しないため、
    # この2つの実行の間は外から見て「削除だけ済んだ中途半端な状態」は見えない
    # （BEGIN〜COMMITで1つのトランザクションにする、というのと同じ効果）。
    with conn.cursor() as cur:
        cur.execute(delete_query, (user_sub,))
        cur.execute(rebuild_query, (user_sub,))
    conn.commit()
