"""core.repository のユニットテスト（DBは使わず、コネクション/カーソルをモックする）。

主眼は「集計ロジック（月・部門・勘定科目ごとの合算）が正しいか」の検証。
実際のSQL発行・DDLとの整合はローカルのPostgreSQLに対する結合テストで別途確認する。
"""

from datetime import date
from unittest.mock import MagicMock

from core.csv_parser import ExpenseRow
from core.repository import insert_audit_log, upsert_summary

# サンプルデータ（6行のうち1行を除いた5行）。
SAMPLE_ROWS = [
    ExpenseRow(date(2026, 7, 1), "SALES", "営業部", "交通費", 3200, "JR東日本", "移動"),
    ExpenseRow(date(2026, 7, 1), "DEV", "開発部", "通信費", 8800, "NTTドコモ", "回線"),
    ExpenseRow(date(2026, 7, 2), "SALES", "営業部", "会議費", 15000, "スターバックス", "打ち合わせ"),
    ExpenseRow(date(2026, 7, 5), "SALES", "営業部", "交通費", 1500, "JR東日本", "移動"),
    ExpenseRow(date(2026, 8, 1), "DEV", "開発部", "通信費", 8800, "NTTドコモ", "回線"),
]


def _mock_connection():
    """本物のDB接続の代わりに使う「偽物」のconn・cursorを作る。"""
    conn = MagicMock()
    cursor = MagicMock()
    conn.cursor.return_value.__enter__.return_value = cursor
    return conn, cursor


def test_upsert_summary_aggregates_same_month_department_category():
    """同じ月・部門・勘定科目の行が複数あるとき、金額が正しく合算されることを確認する。"""
    conn, cursor = _mock_connection()

    upsert_summary(conn, user_sub="user-1", rows=SAMPLE_ROWS)

    # 2026-07 / SALES / 交通費 は 3200 + 1500 = 4700 に集約されるはず
    executed_params = [call.args[1] for call in cursor.execute.call_args_list]
    traffic_expense_call = next(
        p for p in executed_params if p[1] == date(2026, 7, 1) and p[2] == "SALES" and p[4] == "交通費"
    )
    assert traffic_expense_call[5] == 4700


def test_upsert_summary_produces_one_call_per_unique_key():
    """組み合わせ（月・部門・勘定科目）ごとに、execute()がちょうど1回ずつ呼ばれることを確認する。"""
    conn, cursor = _mock_connection()

    upsert_summary(conn, user_sub="user-1", rows=SAMPLE_ROWS)

    # ユニークな (usage_month, department_code, account_category) の組み合わせは4通り
    assert cursor.execute.call_count == 4
    conn.commit.assert_called_once()


def test_insert_audit_log_records_failure_with_error_message():
    """失敗時のログが、正しい引数でINSERTされることを確認する。"""
    conn, cursor = _mock_connection()

    insert_audit_log(conn, user_sub="user-1", file_key="uploads/user-1/x.csv", status="failed", error_message="boom")

    params = cursor.execute.call_args.args[1]
    assert params == ("user-1", "uploads/user-1/x.csv", None, "failed", "boom")
    conn.commit.assert_called_once()
