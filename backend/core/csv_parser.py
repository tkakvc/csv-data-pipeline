"""CSVのパース・バリデーション。"""

from __future__ import annotations

import csv
import io
from dataclasses import dataclass
from datetime import date

REQUIRED_HEADERS = ["利用日", "部門コード", "部門名", "勘定科目", "金額", "取引先", "摘要"]

MAX_FILE_SIZE_BYTES = 10 * 1024 * 1024  # 10MB


class ValidationError(Exception):
    """CSVの内容が不正なときに送出する例外。エラーメッセージは監査ログにそのまま記録される。"""


@dataclass(frozen=True)
class ExpenseRow:
    usage_date: date
    department_code: str
    department_name: str
    account_category: str
    amount: int
    vendor: str | None
    description: str | None


def parse_and_validate(raw_bytes: bytes) -> list[ExpenseRow]:
    """CSVのバイト列を受け取り、検証済みの行データのリストを返す。

    1行でも不正な行があれば ValidationError を送出し、ファイル全体を不採用にする
    （部分的な取込による中途半端な集計を避けるため）。
    """
    if len(raw_bytes) > MAX_FILE_SIZE_BYTES:
        raise ValidationError(f"ファイルサイズが上限（{MAX_FILE_SIZE_BYTES}バイト）を超えています")

    # Excelで保存したCSVはBOM付きになりやすいため、utf-8-sigで吸収する。
    try:
        text = raw_bytes.decode("utf-8-sig")
    except UnicodeDecodeError as e:
        raise ValidationError(f"文字コードがUTF-8として解釈できません: {e}") from e

    reader = csv.DictReader(io.StringIO(text))

    if reader.fieldnames != REQUIRED_HEADERS:
        raise ValidationError(f"ヘッダーが不正です。期待値={REQUIRED_HEADERS}, 実際={reader.fieldnames}")

    # 途中の行でValidationErrorが送出されると、その時点で処理全体が中断し、
    # それ以降の行は一切チェックされない。
    rows = [_validate_row(row, line_number=i) for i, row in enumerate(reader, start=2)]

    if not rows:
        raise ValidationError("データ行が1件もありません")

    return rows


def _validate_row(row: dict, line_number: int) -> ExpenseRow:
    """CSVの1行分（辞書）を検証し、問題なければExpenseRowに変換する。

    チェックは上から順番に行われ、最初に引っかかった項目でValidationErrorを送出して打ち切る
    （同じ行の他の項目に問題があっても、そこまでは確認されない）。
    """
    try:
        usage_date = date.fromisoformat(row["利用日"].strip())
    except (ValueError, AttributeError):
        raise ValidationError(f"{line_number}行目: 利用日の形式が不正です（YYYY-MM-DD形式で入力してください）")

    department_code = (row.get("部門コード") or "").strip()
    department_name = (row.get("部門名") or "").strip()
    account_category = (row.get("勘定科目") or "").strip()

    if not department_code or not department_name or not account_category:
        raise ValidationError(f"{line_number}行目: 部門コード・部門名・勘定科目は必須です")

    amount_text = (row.get("金額") or "").strip()
    try:
        amount = int(amount_text)
    except ValueError:
        raise ValidationError(f"{line_number}行目: 金額が整数として解釈できません（値: {amount_text!r}）")
    if amount < 0:
        raise ValidationError(f"{line_number}行目: 金額は0以上である必要があります")

    vendor = (row.get("取引先") or "").strip() or None
    description = (row.get("摘要") or "").strip() or None

    return ExpenseRow(
        usage_date=usage_date,
        department_code=department_code,
        department_name=department_name,
        account_category=account_category,
        amount=amount,
        vendor=vendor,
        description=description,
    )
