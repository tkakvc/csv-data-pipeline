# backend/

## セットアップ（ローカル）

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt
```

## テストの実行

```bash
cd backend
pytest
```

- `tests/test_csv_parser.py`：CSVのパース・バリデーションのテスト（DB不要）
- `tests/test_ingest.py`：集計ロジック（月・部門・勘定科目ごとの合算）のテスト。DBはモックしており、実際のPostgreSQLには繋がない

## 各Lambda / タスクの動かし方（ローカルでの手動確認）

`DB_SECRET_ARN`等の環境変数はAWS上のリソースを前提にしているため、ローカルでフルに動かすには
実際にSecrets Manager・RDSを用意するか、`core/db.py`の`get_connection()`を差し替える必要がある。
まずは`tests/`のユニットテストで個々のロジックを確認し、結合確認はAWS上に構築してから行う想定。
