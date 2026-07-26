"""core.repository のユニットテスト（DBは使わず、コネクション/カーソルをモックする）。

主眼は「集計ロジック（月・部門・勘定科目ごとの合算）が正しいか」の検証。
実際のSQL発行・DDLとの整合はローカルのPostgreSQLに対する結合テストで別途確認する。
"""

from datetime import date
from unittest.mock import MagicMock

from core.csv_parser import ExpenseRow
from core.repository import insert_audit_log, upsert_summary

# サンプルデータ（6行のうち1行を除いた5行）。
# ExpenseRow(...)は、引数名を書かずに定義順（usage_date, department_code, ...）で値を渡している。
SAMPLE_ROWS = [
    ExpenseRow(date(2026, 7, 1), "SALES", "営業部", "交通費", 3200, "JR東日本", "移動"),
    ExpenseRow(date(2026, 7, 1), "DEV", "開発部", "通信費", 8800, "NTTドコモ", "回線"),
    ExpenseRow(date(2026, 7, 2), "SALES", "営業部", "会議費", 15000, "スターバックス", "打ち合わせ"),
    ExpenseRow(date(2026, 7, 5), "SALES", "営業部", "交通費", 1500, "JR東日本", "移動"),
    ExpenseRow(date(2026, 8, 1), "DEV", "開発部", "通信費", 8800, "NTTドコモ", "回線"),
]


def _mock_connection():
    """本物のDB接続の代わりに使う「偽物」のconn・cursorを作る。

    MagicMock()は「何のメソッドを呼んでも、それらしく応答してくれる偽物オブジェクト」を作るテスト用の道具。
    本物のPostgreSQLに繋がなくても、「execute()が何回呼ばれたか」「どんな引数で呼ばれたか」を
    あとから検証できるようになる。
    """
    conn = MagicMock()
    cursor = MagicMock()
    # repository.py側は "with conn.cursor() as cur:" という書き方をしているため、
    # conn.cursor()の戻り値の「with文に入ったときの値」がcursorになるよう設定している
    conn.cursor.return_value.__enter__.return_value = cursor
    return conn, cursor


def test_upsert_summary_aggregates_same_month_department_category():
    """同じ月・部門・勘定科目の行が複数あるとき、金額が正しく合算されることを確認する。"""
    conn, cursor = _mock_connection()

    upsert_summary(conn, user_sub="user-1", rows=SAMPLE_ROWS)

    # 2026-07 / SALES / 交通費 は 3200 + 1500 = 4700 に集約されるはず
    # cursor.execute.call_args_list は「execute()が呼ばれた回数分の、その時の引数」の一覧。
    # call.args[1] は execute(query, params) の2番目の引数（params）を取り出している。
    executed_params = [call.args[1] for call in cursor.execute.call_args_list]
    # 呼ばれた引数の中から、(月=2026-07-01, 部門=SALES, 勘定科目=交通費) のものを1つ探す
    traffic_expense_call = next(
        p for p in executed_params if p[1] == date(2026, 7, 1) and p[2] == "SALES" and p[4] == "交通費"
    )
    assert traffic_expense_call[5] == 4700  # total_amount（paramsの6番目の要素）


def test_upsert_summary_produces_one_call_per_unique_key():
    """組み合わせ（月・部門・勘定科目）ごとに、execute()がちょうど1回ずつ呼ばれることを確認する。"""
    conn, cursor = _mock_connection()

    upsert_summary(conn, user_sub="user-1", rows=SAMPLE_ROWS)

    # ユニークな (usage_month, department_code, account_category) の組み合わせは4通り
    #   (2026-07, SALES, 交通費) / (2026-07, DEV, 通信費) / (2026-07, SALES, 会議費) / (2026-08, DEV, 通信費)
    assert cursor.execute.call_count == 4
    conn.commit.assert_called_once()  # commit()がちょうど1回だけ呼ばれたことも確認する


def test_insert_audit_log_records_failure_with_error_message():
    """失敗時のログが、正しい引数でINSERTされることを確認する。"""
    conn, cursor = _mock_connection()

    insert_audit_log(conn, user_sub="user-1", file_key="uploads/user-1/x.csv", status="failed", error_message="boom")

    params = cursor.execute.call_args.args[1]
    assert params == ("user-1", "uploads/user-1/x.csv", None, "failed", "boom")
    conn.commit.assert_called_once()
