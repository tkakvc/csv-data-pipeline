"""CSVのパース・バリデーション。"""

from __future__ import annotations

import csv
import io
from dataclasses import dataclass
from datetime import date

# CSVの1行目（ヘッダー行）がこの並び・この列数と完全に一致しないと、
# 「フォーマットが違う」とみなしてエラーにする。
REQUIRED_HEADERS = ["利用日", "部門コード", "部門名", "勘定科目", "金額", "取引先", "摘要"]

MAX_FILE_SIZE_BYTES = 10 * 1024 * 1024  # 10MB


class ValidationError(Exception):
    """CSVの内容が不正なときに送出する例外。エラーメッセージは監査ログにそのまま記録される。"""
    # Exceptionを継承しているだけの「印」のようなクラス。
    # raise ValidationError("...") と書くと、その場で処理が中断し、
    # 呼び出し側の except ValidationError as e: まで一気に飛んでいく。
    # 呼び出し側は e をそのままエラーメッセージとして使っている。


@dataclass(frozen=True)
class ExpenseRow:
    # @dataclass は「メンバ変数を書くだけで、__init__などの定型コードを自動生成してくれる」機能。
    # 例えば ExpenseRow(date(2026,7,1), "SALES", ...) のように、
    # ここに並んだ順番で値を渡すとインスタンス（実際のデータの入れ物）が作れる。
    # frozen=True は「一度作ったら値を書き換えられない（読み取り専用）」という指定。
    usage_date: date        # 利用日
    department_code: str    # 部門コード
    department_name: str    # 部門名
    account_category: str   # 勘定科目
    amount: int              # 金額
    vendor: str | None       # 取引先（空欄ならNone。"str | None" は「文字列 または None」という型の意味）
    description: str | None  # 摘要（空欄ならNone）


def parse_and_validate(raw_bytes: bytes) -> list[ExpenseRow]:
    """CSVのバイト列を受け取り、検証済みの行データのリストを返す。

    1行でも不正な行があれば ValidationError を送出し、ファイル全体を不採用にする
    （部分的な取込による中途半端な集計を避けるため）。
    """
    # ① ファイルサイズのチェック（10MBを超えていたら中身を見るまでもなくエラー）
    if len(raw_bytes) > MAX_FILE_SIZE_BYTES:
        raise ValidationError(f"ファイルサイズが上限（{MAX_FILE_SIZE_BYTES}バイト）を超えています")

    # ② バイト列（0/1の羅列）を、人間が読める文字列（テキスト）に変換する処理。
    #    "utf-8-sig" は「BOM付きUTF-8」も許容するデコード方式。
    #    Excelで保存したCSVはBOM付きになりやすいため、ここで吸収している。
    try:
        text = raw_bytes.decode("utf-8-sig")
    except UnicodeDecodeError as e:
        raise ValidationError(f"文字コードがUTF-8として解釈できません: {e}") from e

    # ③ csv.DictReaderは「1行ごとに、ヘッダー名をキーにした辞書」を返してくれる読み込み器。
    #    例：{"利用日": "2026-07-01", "部門コード": "SALES", ...}
    #    io.StringIO(text) は「文字列をファイルのように扱えるようにする」ためのラッパー。
    reader = csv.DictReader(io.StringIO(text))

    # ④ ヘッダー行が期待通りの列名・並び・列数でなければエラー
    if reader.fieldnames != REQUIRED_HEADERS:
        raise ValidationError(f"ヘッダーが不正です。期待値={REQUIRED_HEADERS}, 実際={reader.fieldnames}")

    # ⑤ 2行目以降を1行ずつ_validate_row()でチェックし、問題なければExpenseRowに変換する。
    #    これは「リスト内包表記」というPythonの書き方で、下のfor文と同じ意味。
    #      rows = []
    #      for i, row in enumerate(reader, start=2):
    #          rows.append(_validate_row(row, line_number=i))
    #    enumerate(reader, start=2) は「readerから1行ずつ取り出しつつ、
    #    2から始まる連番（CSVファイル上の実際の行番号）も一緒に取り出す」という意味。
    #    途中の行で_validate_rowがValidationErrorを送出すると、
    #    その時点でこの処理全体が中断し、それ以降の行は一切チェックされない。
    rows = [_validate_row(row, line_number=i) for i, row in enumerate(reader, start=2)]

    # ⑥ データ行が1行も無い（ヘッダーだけの）CSVもエラーにする
    if not rows:
        raise ValidationError("データ行が1件もありません")

    return rows


def _validate_row(row: dict, line_number: int) -> ExpenseRow:
    """CSVの1行分（辞書）を検証し、問題なければExpenseRowに変換する。

    チェックは上から順番に行われ、最初に引っかかった項目でValidationErrorを送出して打ち切る
    （同じ行の他の項目に問題があっても、そこまでは確認されない）。
    """
    # 利用日のチェック：YYYY-MM-DD形式として解釈できるか
    try:
        usage_date = date.fromisoformat(row["利用日"].strip())
    except (ValueError, AttributeError):
        raise ValidationError(f"{line_number}行目: 利用日の形式が不正です（YYYY-MM-DD形式で入力してください）")

    # 部門コード・部門名・勘定科目のチェック：空文字は禁止
    # row.get("部門コード") は、キーが存在しなくてもエラーにならず None を返す取り出し方。
    # "(... or '')" は「Noneだったら空文字として扱う」という意味。
    department_code = (row.get("部門コード") or "").strip()
    department_name = (row.get("部門名") or "").strip()
    account_category = (row.get("勘定科目") or "").strip()

    if not department_code or not department_name or not account_category:
        raise ValidationError(f"{line_number}行目: 部門コード・部門名・勘定科目は必須です")

    # 金額のチェック：整数に変換できるか、かつ0以上か
    amount_text = (row.get("金額") or "").strip()
    try:
        amount = int(amount_text)
    except ValueError:
        raise ValidationError(f"{line_number}行目: 金額が整数として解釈できません（値: {amount_text!r}）")
    if amount < 0:
        raise ValidationError(f"{line_number}行目: 金額は0以上である必要があります")

    # 取引先・摘要は任意項目。空文字なら None（DB上はNULL）として扱う。
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
