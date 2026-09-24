# データベース設計（PostgreSQL）

- 前提：CSVフォーマットは [csv-format.md](./csv-format.md) に基づく
- 対象DB：RDS for PostgreSQL
- 命名規則：テーブル名・カラム名はすべて英語のスネークケース（小文字＋アンダースコア）

---

## 1. テーブル一覧

| テーブル物理名 | 役割 |
|---|---|
| `raw_expenses` | CSVの各行をほぼそのまま保存する生データテーブル |
| `summary_expenses` | 月・部門・勘定科目単位で金額を合計した集計テーブル |
| `upload_audit_log` | 誰が・いつ・どのファイルをアップロードし、成功したか失敗したかの記録 |

---

## 2. テーブル定義

### 2-1 `raw_expenses`（経費生データ）

| No | 物理名 | データ型 | NULL | キー | 説明 |
|---|---|---|---|---|---|
| 1 | `id` | BIGSERIAL | NOT NULL | PK | 自動採番 |
| 2 | `user_sub` | VARCHAR(255) | NOT NULL | IDX | GoogleのIDトークンに含まれる`sub`クレーム |
| 3 | `source_file_key` | VARCHAR(1024) | NOT NULL | IDX | 元になったCSVファイルのS3オブジェクトキー |
| 4 | `usage_date` | DATE | NOT NULL | - | 経費が発生した日 |
| 5 | `department_code` | VARCHAR(50) | NOT NULL | - | 部門コード（例：`SALES`） |
| 6 | `department_name` | VARCHAR(100) | NOT NULL | - | 部門名（例：`営業部`） |
| 7 | `account_category` | VARCHAR(100) | NOT NULL | - | 勘定科目（例：`交通費`） |
| 8 | `amount` | INTEGER | NOT NULL | - | 支出額（円）。`CHECK (amount >= 0)` |
| 9 | `vendor` | VARCHAR(255) | NULL可 | - | 取引先 |
| 10 | `description` | TEXT | NULL可 | - | 摘要 |
| 11 | `uploaded_at` | TIMESTAMPTZ | NOT NULL | - | DB登録日時（デフォルト`now()`） |

```sql
CREATE TABLE raw_expenses (
    id               BIGSERIAL PRIMARY KEY,
    user_sub         VARCHAR(255) NOT NULL,
    source_file_key  VARCHAR(1024) NOT NULL,
    usage_date       DATE NOT NULL,
    department_code  VARCHAR(50) NOT NULL,
    department_name  VARCHAR(100) NOT NULL,
    account_category VARCHAR(100) NOT NULL,
    amount           INTEGER NOT NULL CHECK (amount >= 0),
    vendor           VARCHAR(255),
    description      TEXT,
    uploaded_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_raw_expenses_user_sub    ON raw_expenses (user_sub);
CREATE INDEX idx_raw_expenses_usage_date  ON raw_expenses (usage_date);
CREATE INDEX idx_raw_expenses_source_file ON raw_expenses (source_file_key);
```

### 2-2 `summary_expenses`（経費集計データ）

| No | 物理名 | データ型 | NULL | キー | 説明 |
|---|---|---|---|---|---|
| 1 | `id` | BIGSERIAL | NOT NULL | PK | 自動採番 |
| 2 | `user_sub` | VARCHAR(255) | NOT NULL | IDX／UNIQUE(複合) | ユーザー識別子 |
| 3 | `usage_month` | DATE | NOT NULL | IDX／UNIQUE(複合) | 集計対象月（月初日で表現。例：`2026-07-01`） |
| 4 | `department_code` | VARCHAR(50) | NOT NULL | UNIQUE(複合) | 部門コード |
| 5 | `department_name` | VARCHAR(100) | NOT NULL | - | 部門名 |
| 6 | `account_category` | VARCHAR(100) | NOT NULL | UNIQUE(複合) | 勘定科目 |
| 7 | `total_amount` | INTEGER | NOT NULL | - | 合計金額。`CHECK (total_amount >= 0)` |
| 8 | `updated_at` | TIMESTAMPTZ | NOT NULL | - | 最終更新日時 |

- 複合UNIQUE制約：`(user_sub, usage_month, department_code, account_category)` の組み合わせで1レコードに一意化し、同じ組み合わせの集計値はUPSERTで1行にまとめる（3章）

```sql
CREATE TABLE summary_expenses (
    id               BIGSERIAL PRIMARY KEY,
    user_sub         VARCHAR(255) NOT NULL,
    usage_month      DATE NOT NULL,
    department_code  VARCHAR(50) NOT NULL,
    department_name  VARCHAR(100) NOT NULL,
    account_category VARCHAR(100) NOT NULL,
    total_amount     INTEGER NOT NULL CHECK (total_amount >= 0),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_sub, usage_month, department_code, account_category)
);

CREATE INDEX idx_summary_expenses_user_sub    ON summary_expenses (user_sub);
CREATE INDEX idx_summary_expenses_usage_month ON summary_expenses (usage_month);
```

### 2-3 `upload_audit_log`（アップロード監査ログ）

| No | 物理名 | データ型 | NULL | キー | 説明 |
|---|---|---|---|---|---|
| 1 | `id` | BIGSERIAL | NOT NULL | PK | 自動採番 |
| 2 | `user_sub` | VARCHAR(255) | NOT NULL | IDX | アップロードを行ったユーザー |
| 3 | `file_key` | VARCHAR(1024) | NOT NULL | UNIQUE | アップロードされたCSVファイルのS3オブジェクトキー |
| 4 | `row_count` | INTEGER | NULL可 | - | 取込行数。`processing`中・失敗時はNULL |
| 5 | `status` | VARCHAR(20) | NOT NULL | - | `processing`／`success`／`failed`のいずれか。`CHECK`制約あり |
| 6 | `error_message` | TEXT | NULL可 | - | 失敗時のエラー内容 |
| 7 | `processed_at` | TIMESTAMPTZ | NOT NULL | - | 予約時・確定時に更新される日時 |

**べき等性の設計（`file_key` UNIQUE + `processing` 状態）**

S3のイベント通知は「最低1回配信」であり、同一アップロードに対してCSV取込Lambdaが重複して呼び出される可能性がある。対策として、Lambdaは処理の一番最初に`file_key`を`status='processing'`で予約INSERTする（`INSERT ... ON CONFLICT (file_key) DO NOTHING RETURNING id`）。

- 予約に成功（行が返る）→ 処理を進め、完了後に同じ行を`success`/`failed`に更新する
- 予約に失敗（`file_key`のUNIQUE制約に阻まれ、行が返らない）→ 既に別の呼び出しが予約済み（重複配信）と判断し、`raw_expenses`・`summary_expenses`への書き込みを一切行わずに終了する

これにより、同じファイルが2回配信されても集計金額が二重に加算されることはない。なお、予約後に処理が例外で失敗すると行は`processing`のまま残り、再配信されても「予約済み」としてスキップされ続ける。重複配信によるデータ二重化の防止を主目的とし、失敗した予約の自動リトライまでは対象外としている（発生時は運用でその行を削除する想定）。

```sql
CREATE TABLE upload_audit_log (
    id             BIGSERIAL PRIMARY KEY,
    user_sub       VARCHAR(255) NOT NULL,
    file_key       VARCHAR(1024) NOT NULL UNIQUE,
    row_count      INTEGER,
    status         VARCHAR(20) NOT NULL CHECK (status IN ('processing', 'success', 'failed')),
    error_message  TEXT,
    processed_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_upload_audit_log_user_sub ON upload_audit_log (user_sub);
```

---

## 3. UPSERTの実装（`summary_expenses`への書き込み）

```sql
INSERT INTO summary_expenses
    (user_sub, usage_month, department_code, department_name, account_category, total_amount)
VALUES
    (%(user_sub)s, %(usage_month)s, %(department_code)s, %(department_name)s, %(account_category)s, %(amount)s)
ON CONFLICT (user_sub, usage_month, department_code, account_category)
DO UPDATE SET
    total_amount = summary_expenses.total_amount + EXCLUDED.total_amount,
    updated_at   = now();
```

- `%(...)s`はPythonの`psycopg2`でのプレースホルダ記法（パラメータ化クエリ）
- `usage_month`は、CSVの`利用日`から日付部分を切り捨てて月初日にする（例：`2026-07-15` → `2026-07-01`）

---

## 4. バックフィル時のSQL

バックフィルは「1件アップロード分を足し込む」のではなく、「summaryを空にしてrawから作り直す」処理にする（加算方式だと過去に間違って加算した分と正しい分が混ざってしまうため）。

```sql
BEGIN;

DELETE FROM summary_expenses WHERE user_sub = %(user_sub)s;

INSERT INTO summary_expenses
    (user_sub, usage_month, department_code, department_name, account_category, total_amount)
SELECT
    user_sub,
    date_trunc('month', usage_date)::date AS usage_month,
    department_code,
    department_name,
    account_category,
    SUM(amount) AS total_amount
FROM raw_expenses
WHERE user_sub = %(user_sub)s
GROUP BY user_sub, date_trunc('month', usage_date), department_code, department_name, account_category;

COMMIT;
```

- `user_sub`ごとに実行する（マルチユーザーで使う場合、他ユーザーのsummaryを巻き込まないため）
- `BEGIN`〜`COMMIT`で1つのトランザクションにし、`DELETE`と`INSERT`の間で読み取りが発生してもsummaryが空の状態を見せないようにする

---

## 5. サンプルデータ投入後の状態イメージ

[csv-format.md](./csv-format.md)のサンプルCSVを、`user_sub = "google-oauth2|12345"`としてアップロードした場合。

```
raw_expenses（6行、CSVの行数と同じ）
| id | usage_date | department_code | account_category | amount | vendor       |
| 1  | 2026-07-01 | SALES            | 交通費            | 3200   | JR東日本     |
| 2  | 2026-07-01 | DEV              | 通信費            | 8800   | NTTドコモ    |
| 3  | 2026-07-02 | SALES            | 会議費            | 15000  | スターバックス |
| 4  | 2026-07-03 | HR               | 消耗品費          | 4500   | Amazon       |
| 5  | 2026-07-05 | SALES            | 交通費            | 1500   | JR東日本     |
| 6  | 2026-08-01 | DEV              | 通信費            | 8800   | NTTドコモ    |

summary_expenses（月・部門・勘定科目ごとに集約される）
| usage_month | department_code | account_category | total_amount |
| 2026-07-01  | SALES            | 交通費            | 4700         |  ← id1(3200) + id5(1500)
| 2026-07-01  | DEV              | 通信費            | 8800         |
| 2026-07-01  | SALES            | 会議費            | 15000        |
| 2026-07-01  | HR               | 消耗品費          | 4500         |
| 2026-08-01  | DEV              | 通信費            | 8800         |
```
