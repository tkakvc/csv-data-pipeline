"""core.csv_parser のユニットテスト。"""

from datetime import date

import pytest

from core.csv_parser import ExpenseRow, ValidationError, parse_and_validate

# 正常なCSVのサンプル。.encode("utf-8")で文字列をバイト列に変換している
# （parse_and_validateはバイト列を受け取る関数なので、テストでもバイト列を渡す必要がある）。
VALID_CSV = (
    "利用日,部門コード,部門名,勘定科目,金額,取引先,摘要\n"
    "2026-07-01,SALES,営業部,交通費,3200,JR東日本,顧客訪問のための移動\n"
    "2026-07-01,DEV,開発部,通信費,8800,NTTドコモ,業務用回線\n"
    "2026-07-02,SALES,営業部,会議費,15000,スターバックス,顧客打ち合わせ\n"
    "2026-07-03,HR,人事部,消耗品費,4500,Amazon,オフィス用品\n"
    "2026-07-05,SALES,営業部,交通費,1500,JR東日本,顧客訪問のための移動\n"
    "2026-08-01,DEV,開発部,通信費,8800,NTTドコモ,業務用回線\n"
).encode("utf-8")


# pytestは「test_ から始まる関数」を自動的にテストとして実行してくれるツール。
# 関数の中のassert（「これが真であるはず」という表明）が全部通れば成功、
# 1つでも成り立たなければそのテストは失敗として報告される。

def test_parse_and_validate_returns_all_rows():
    """正常なCSVを渡したら、6行分すべてがExpenseRowに変換されて返ってくることを確認する。"""
    rows = parse_and_validate(VALID_CSV)

    assert len(rows) == 6
    assert rows[0] == ExpenseRow(
        usage_date=date(2026, 7, 1),
        department_code="SALES",
        department_name="営業部",
        account_category="交通費",
        amount=3200,
        vendor="JR東日本",
        description="顧客訪問のための移動",
    )


def test_parse_and_validate_accepts_bom():
    """BOM（ファイル先頭に付く特殊な3バイト）付きのCSVでも正しく読めることを確認する。"""
    bom_csv = b"\xef\xbb\xbf" + VALID_CSV  # \xef\xbb\xbf がUTF-8のBOMのバイト列
    rows = parse_and_validate(bom_csv)
    assert len(rows) == 6


def test_parse_and_validate_allows_empty_optional_columns():
    """取引先・摘要が空欄の行は、エラーにならずvendor/descriptionがNoneになることを確認する。"""
    csv_bytes = (
        "利用日,部門コード,部門名,勘定科目,金額,取引先,摘要\n"
        "2026-07-01,SALES,営業部,交通費,3200,,\n"
    ).encode("utf-8")

    rows = parse_and_validate(csv_bytes)

    assert rows[0].vendor is None
    assert rows[0].description is None


def test_parse_and_validate_rejects_wrong_header():
    """ヘッダー行が期待した列名と違う場合にValidationErrorが発生することを確認する。

    pytest.raises(...) は「withブロックの中でこの例外が発生すること」を確認する書き方。
    match=... は、例外メッセージにその文字列が含まれているかも一緒にチェックする。
    """
    csv_bytes = "date,dept,category,amount\n2026-07-01,SALES,交通費,3200\n".encode("utf-8")

    with pytest.raises(ValidationError, match="ヘッダーが不正です"):
        parse_and_validate(csv_bytes)


def test_parse_and_validate_rejects_invalid_date():
    """利用日が YYYY-MM-DD 形式でない（"/"区切りなど）場合にエラーになることを確認する。"""
    csv_bytes = (
        "利用日,部門コード,部門名,勘定科目,金額,取引先,摘要\n"
        "2026/07/01,SALES,営業部,交通費,3200,JR東日本,移動\n"
    ).encode("utf-8")

    with pytest.raises(ValidationError, match="利用日の形式が不正です"):
        parse_and_validate(csv_bytes)


def test_parse_and_validate_rejects_missing_required_field():
    """部門コード・部門名・勘定科目のいずれかが空文字の場合にエラーになることを確認する。"""
    csv_bytes = (
        "利用日,部門コード,部門名,勘定科目,金額,取引先,摘要\n"
        "2026-07-01,,営業部,交通費,3200,JR東日本,移動\n"
    ).encode("utf-8")

    with pytest.raises(ValidationError, match="必須です"):
        parse_and_validate(csv_bytes)


def test_parse_and_validate_rejects_non_numeric_amount():
    """金額が数字に変換できない文字列（"abc"など）の場合にエラーになることを確認する。"""
    csv_bytes = (
        "利用日,部門コード,部門名,勘定科目,金額,取引先,摘要\n"
        "2026-07-01,SALES,営業部,交通費,abc,JR東日本,移動\n"
    ).encode("utf-8")

    with pytest.raises(ValidationError, match="金額が整数として解釈できません"):
        parse_and_validate(csv_bytes)


def test_parse_and_validate_rejects_negative_amount():
    """金額が負の数の場合にエラーになることを確認する。"""
    csv_bytes = (
        "利用日,部門コード,部門名,勘定科目,金額,取引先,摘要\n"
        "2026-07-01,SALES,営業部,交通費,-100,JR東日本,移動\n"
    ).encode("utf-8")

    with pytest.raises(ValidationError, match="0以上である必要があります"):
        parse_and_validate(csv_bytes)


def test_parse_and_validate_rejects_empty_file():
    """ヘッダー行しかなく、データ行が1件も無い場合にエラーになることを確認する。"""
    csv_bytes = "利用日,部門コード,部門名,勘定科目,金額,取引先,摘要\n".encode("utf-8")

    with pytest.raises(ValidationError, match="データ行が1件もありません"):
        parse_and_validate(csv_bytes)


def test_parse_and_validate_rejects_oversized_file():
    """ファイルサイズが10MBを超える場合にエラーになることを確認する。"""
    huge = b"a" * (10 * 1024 * 1024 + 1)  # 10MB + 1バイトのダミーデータ

    with pytest.raises(ValidationError, match="ファイルサイズが上限"):
        parse_and_validate(huge)
