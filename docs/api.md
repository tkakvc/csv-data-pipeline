# API仕様書

- 前提：DBスキーマは [database.md](./database.md)、認証方式は [architecture.md](./architecture.md) 4-1

---

## 0. 共通仕様

### 0-1 エンドポイント一覧

| API名 | メソッド・パス | 認証 | 概要 |
|---|---|---|---|
| 署名付きURL発行API | `POST /upload-url` | 必須 | CSVアップロード用のS3署名付きURLを発行する |
| 読み取り専用API | `GET /summary` | 必須 | 集計結果を取得する |

### 0-2 認証方式

全APIはAPI Gateway（HTTP API）+ Lambdaで構成し、GoogleのJWKSエンドポイントで自前検証するLambda Authorizerで保護する（Cognitoは使わない。比較は[architecture.md](./architecture.md) 7-4）。

**共通リクエストヘッダー**

| ヘッダー名 | 必須 | 説明 |
|---|---|---|
| `Authorization` | 必須 | `Bearer <Google IDトークン>` 形式。Lambda AuthorizerがGoogleのJWKSで署名検証する |

リクエストの流れ（`POST /upload-url`の例）：

```
クライアント → POST /upload-url（Authorizationヘッダー付き）

① API Gatewayが受信 → メソッドとパスを見てルートを判断
② API GatewayがLambda Authorizerを呼び出す
   → JWTをGoogleのJWKSで検証させ、「通していいか」だけを返させる
③ 通してよければAPI Gatewayが本来の処理用Lambdaを呼び出す
   → subを取り出し、S3の署名付きURLを発行する
④ そのLambdaのレスポンスを、API Gatewayがそのままクライアントに返す
```

2つのエンドポイント（`POST /upload-url`・`GET /summary`）は同じ1つのAPI Gatewayインスタンスの下に別々のルートとして登録されており、Lambda Authorizerは共通、処理用Lambdaはエンドポイントごとに別、という1対多の構造になっている。

### 0-3 共通エラーレスポンス

- 形式：`{ "error": { "code": "...", "message": "..." } }`

| コード | 意味 | HTTPステータス |
|---|---|---|
| `UNAUTHORIZED` | 認証トークンが無い、または無効 | 401 |
| `VALIDATION_ERROR` | リクエストの内容が不正（例：`month`パラメータが`YYYY-MM`形式でない） | 400 |
| `INTERNAL_ERROR` | サーバー内部エラー | 500 |

---

## 1. 署名付きURL発行API

### `POST /upload-url`

CSVファイルをS3に直接アップロードするための、署名付きURL（一時的な書き込み許可証）を発行する。

**リクエストヘッダー**

| ヘッダー名 | 必須 | 説明 |
|---|---|---|
| `Authorization` | 必須 | `Bearer <Google IDトークン>` |

**リクエストボディ**：なし（保存先パスはクライアントから送らず、トークンの`sub`からLambda側で組み立てる）

**レスポンス（200 OK）**

| 項目名 | 型 | 説明 |
|---|---|---|
| `url` | string | S3への署名付きPUT URL。有効期限内に限りこのURLへPUTできる |
| `key` | string | 発行したURLが指すS3オブジェクトキー（`uploads/{sub}/{タイムスタンプ}_costs.csv`） |
| `expiresIn` | number | `url`の有効期限（秒）。300固定 |

```json
{
  "url": "https://cost-csv-bucket.s3.ap-northeast-1.amazonaws.com/uploads/google-oauth2%7C12345/20260720T120000Z_costs.csv?X-Amz-Algorithm=AWS4-HMAC-SHA256&...",
  "key": "uploads/google-oauth2|12345/20260720T120000Z_costs.csv",
  "expiresIn": 300
}
```

**処理内容**

1. `Authorization`ヘッダーからJWTを取り出し、Googleの公開鍵（JWKS）で署名を検証する
2. JWTから`sub`クレームを取り出す
3. 保存先キーを `uploads/{sub}/{ISO8601形式のタイムスタンプ}_costs.csv` として組み立てる（クライアントからのパス指定は受け付けない）
4. `boto3`の`generate_presigned_url('put_object', ...)`でURLを発行する
5. 発行したURL・キー・有効期限を返す

---

## 2. 読み取り専用API

### `GET /summary`

ログイン中のユーザー自身の集計結果を取得する。

**クエリパラメータ**

| 項目名 | 型 | 必須 | 説明 |
|---|---|---|---|
| `month` | string（`YYYY-MM`形式） | 任意 | 指定時はその月のデータのみに絞り込む。省略時は全期間 |

**レスポンス（200 OK）**

```json
{
  "items": [
    {
      "usageMonth": "2026-07",
      "departmentCode": "SALES",
      "departmentName": "営業部",
      "accountCategory": "交通費",
      "totalAmount": 4700
    }
  ]
}
```

**処理内容**

1. JWTを検証し、`sub`を取り出す
2. `SELECT ... FROM summary_expenses WHERE user_sub = %(sub)s [AND usage_month = %(month)s] ORDER BY usage_month DESC, department_code, account_category`
3. 結果をJSON配列に変換して返す（他ユーザーのデータは`WHERE user_sub = ...`により取得できない）

---

## 3. CSV取込Lambdaの入出力

REST APIではなく、S3のイベント通知から直接呼び出される非同期処理。

**入力（S3イベント通知のペイロード。抜粋）**

```json
{
  "Records": [
    {
      "eventName": "ObjectCreated:Put",
      "s3": {
        "bucket": { "name": "cost-csv-bucket" },
        "object": { "key": "uploads/google-oauth2%7C12345/20260720T120000Z_costs.csv" }
      }
    }
  ]
}
```

**処理内容**

1. `key`から`sub`を取り出す（`uploads/{sub}/{filename}`という命名規則）
2. `upload_audit_log`にこの`file_key`を`status='processing'`で予約INSERTする（[database.md](./database.md)のべき等性設計を参照）。既に予約済み（＝重複配信）なら、以降の処理を行わずここで終了する
3. S3から該当オブジェクトを取得する
4. [csv-format.md](./csv-format.md)のバリデーションルールに従ってパース・検証する
5. 検証NGの場合：`upload_audit_log`の予約行を`status='failed'`に更新して終了
6. 検証OKの場合：`raw_expenses`へ全行INSERT → `summary_expenses`へUPSERT → `upload_audit_log`の予約行を`status='success'`・`row_count`とともに更新

---

## 4. バックフィルFargateタスクの入出力

REST APIではなく、`aws ecs run-task`で起動する。

```bash
aws ecs run-task \
  --cluster cost-csv-cluster \
  --task-definition backfill-task \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[...],securityGroups=[...],assignPublicIp=DISABLED}"
```

- 特定ユーザーだけ再集計したい場合は、`--overrides`で`TARGET_USER_SUB`を上書きする（省略時は全ユーザー対象）

**環境変数**

| 変数名 | 必須 | 説明 |
|---|---|---|
| `TARGET_USER_SUB` | 任意 | 再集計対象のユーザー（`sub`）。省略時は全ユーザー対象 |
| `DB_SECRET_ARN` | 必須 | RDS接続情報が入ったSecrets ManagerのARN |

**処理内容**

1. `DB_SECRET_ARN`からRDSの接続情報を取得する
2. [database.md](./database.md) 4章のSQL（`DELETE`→`INSERT ... SELECT ... GROUP BY`）を、対象ユーザーごとに実行する
3. 処理結果（対象ユーザー数・処理件数）をCloudWatch Logsに出力して終了する
