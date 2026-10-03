# コストデータ取込・分析システム（CSV Data Pipeline）

CSVをアップロードするだけで、解析・DB取り込み・集計までを自動化するシステム。実務で経験したCSV取込・データ移行パイプラインの構成を、AWSインフラ設計から自分の裁量で作り直したポートフォリオ。

🔗 **デモ：[https://csv.okuyamat.click/](https://csv.okuyamat.click/)**（Googleアカウントでのログインが必要です。ログイン不要で画面を見たい場合は下のスクリーンショットをご覧ください。アップロード画面からサンプルCSVをダウンロードして試せます）

| ログイン | アップロード | 集計結果 |
|---|---|---|
| ![ログイン画面](./frontend/public/screenshots/login.png) | ![アップロード画面](./frontend/public/screenshots/upload.png) | ![集計結果画面](./frontend/public/screenshots/summary.png) |

---

## これは何のためのプロジェクトか

これまで実務では、他部署から届く費用（コスト）データのCSVを、担当者が手作業でExcelに転記・集計していた。転記ミス・属人化・集計のやり直しといった課題を、「アップロードするだけで自動的に集計結果が最新化される」仕組みに置き換えるとどうなるかを、個人開発として一から設計・構築した。

もう1つのポートフォリオ [career-support-app](../career-support-app)（学習記録PF）ではバックエンド・フロントエンドの実装力を、このプロジェクトでは **AWSインフラ設計・データパイプライン構築** に力点を置いている。

| | career-support-app（学習記録PF） | 本プロジェクト（ETL PF） |
|---|---|---|
| 証明する力 | バックエンド・フロントエンドの実装力 | AWSインフラ設計・データパイプライン構築 |
| アーキテクチャ | ECS Fargate（常時起動のWebアプリ） | イベント駆動（S3→Lambda）＋バックフィル用Fargate |
| 認証方式 | 自前JWT | OIDC（Google） |
| 実務との関係 | ポートフォリオとして新規設計 | 実務で経験した構成の再現 |

---

## アーキテクチャ

```mermaid
flowchart TD
    User["利用者（ブラウザ）"]
    Upload["①CSVアップロード画面<br/>React + Vite"]
    Summary["⑦集計結果表画面<br/>React + Vite"]
    CF["CloudFront"]
    PresignAPI["⓪署名付きURL発行API<br/>API Gateway + Lambda"]
    S3["②S3<br/>CSV保存バケット"]
    IngestLambda["④CSV取込Lambda<br/>解析・バリデーション・集計"]
    RDS[("⑤RDS PostgreSQL<br/>raw / summary / audit_log")]
    SummaryAPI["⑥読み取り専用API<br/>API Gateway + Lambda"]
    Backfill["⑧バックフィルFargateタスク"]
    Google["Google OIDC"]

    User -->|HTTPS| CF --> Upload
    CF --> Summary
    Upload -->|1: アップロード許可を要求| PresignAPI
    PresignAPI -->|2: 署名付きURLを発行| Upload
    Upload -->|3: 署名付きURLでPUT| S3
    S3 -->|4: アップロード検知| IngestLambda
    IngestLambda -->|5: INSERT / UPSERT| RDS
    Summary -->|集計結果を取得| SummaryAPI
    SummaryAPI -->|SELECT| RDS
    PresignAPI -. JWT検証 .-> Google
    SummaryAPI -. JWT検証 .-> Google
    Backfill -.->|管理者が手動実行<br/>再集計| RDS
```

- 詳細な設計判断・比較検討した代替案（Athena・Cognito・Fargate等の不採用理由）は [docs/architecture.md](./docs/architecture.md)
- ネットワーク設計（VPC・サブネット・SG）は [docs/network.md](./docs/network.md)
- セキュリティレビューの指摘一覧・対応方針は [docs/security.md](./docs/security.md)

---

## 使用技術

| 領域 | 技術 |
|---|---|
| フロントエンド | React 19 + TypeScript + Vite、TanStack Query、axios、Tailwind CSS v4、shadcn/ui、react-router-dom |
| バックエンド | Python（Lambda 3本 + Fargateタスク）、psycopg2 |
| データベース | Amazon RDS for PostgreSQL |
| 認証 | OIDC（Googleでログイン）、Lambda AuthorizerによるJWT自前検証（JWKS） |
| インフラ | API Gateway（HTTP API）、S3、CloudFront、ECS Fargate + ECR、Secrets Manager、IAM |
| 配信 | S3 + CloudFront（静的ホスティング） |

新しく学んだのは実質 **Lambda（イベント駆動処理）・API Gateway・OIDC認証（Google・自前トークン検証）・VPC設計** の4つ。他はもう1つのポートフォリオで学んだ内容の応用。

---

## データベース設計

| テーブル | 役割 |
|---|---|
| `raw_expenses` | CSVの各行をほぼそのまま保存する生データ |
| `summary_expenses` | 月・部門・勘定科目単位で金額を合計した集計データ |
| `upload_audit_log` | 誰が・いつ・どのファイルをアップロードし、成功/失敗したかの記録 |

<details>
<summary>各テーブルのカラム定義</summary>

**`raw_expenses`**

| 物理名 | 型 | 説明 |
|---|---|---|
| `id` | BIGSERIAL | PK |
| `user_sub` | VARCHAR(255) | GoogleのIDトークンに含まれる`sub` |
| `source_file_key` | VARCHAR(1024) | 元CSVのS3オブジェクトキー |
| `usage_date` | DATE | 経費が発生した日 |
| `department_code` / `department_name` | VARCHAR | 部門コード・部門名 |
| `account_category` | VARCHAR(100) | 勘定科目 |
| `amount` | INTEGER | 支出額（`CHECK (amount >= 0)`） |
| `vendor` / `description` | VARCHAR / TEXT | 取引先・摘要（NULL可） |
| `uploaded_at` | TIMESTAMPTZ | DB登録日時 |

**`summary_expenses`**

| 物理名 | 型 | 説明 |
|---|---|---|
| `id` | BIGSERIAL | PK |
| `user_sub` / `usage_month` / `department_code` / `account_category` | - | 複合UNIQUE制約（この4つの組み合わせで1行に集約） |
| `department_name` | VARCHAR(100) | 部門名 |
| `total_amount` | INTEGER | 合計金額 |
| `updated_at` | TIMESTAMPTZ | 最終更新日時 |

**`upload_audit_log`**

| 物理名 | 型 | 説明 |
|---|---|---|
| `id` | BIGSERIAL | PK |
| `user_sub` | VARCHAR(255) | アップロードした人 |
| `file_key` | VARCHAR(1024) | UNIQUE。同一ファイルの重複INSERTを防ぐべき等性の関所 |
| `row_count` | INTEGER | 取込行数（`processing`中・失敗時はNULL） |
| `status` | VARCHAR(20) | `processing` / `success` / `failed` |
| `error_message` | TEXT | 失敗時のエラー内容 |
| `processed_at` | TIMESTAMPTZ | 予約・確定時に更新される日時 |

全DDL・UPSERT文・バックフィル時のSQLは [docs/database.md](./docs/database.md) を参照。

</details>

---

## API設計

| API | メソッド・パス | 認証 | 概要 |
|---|---|---|---|
| 署名付きURL発行API | `POST /upload-url` | 必須 | CSVアップロード用のS3署名付きURLを発行する |
| 読み取り専用API | `GET /summary` | 必須 | 集計結果を取得する（`month`パラメータで絞り込み可） |

<details>
<summary>リクエスト・レスポンス例</summary>

**`POST /upload-url`**

リクエストボディ無し（保存先パスはクライアントから送らず、トークンの`sub`からLambda側で組み立てる）。

```json
// 200 OK
{
  "url": "https://cost-csv-bucket.s3.ap-northeast-1.amazonaws.com/uploads/...（署名付き）",
  "key": "uploads/google-oauth2|12345/20260720T120000Z_costs.csv",
  "expiresIn": 300
}
```

**`GET /summary?month=2026-07`**

```json
// 200 OK
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

**共通エラー形式**

```json
{ "error": { "code": "UNAUTHORIZED", "message": "..." } }
```

| コード | 意味 | HTTPステータス |
|---|---|---|
| `UNAUTHORIZED` | 認証トークンが無い、または無効 | 401 |
| `VALIDATION_ERROR` | リクエストの内容が不正 | 400 |
| `INTERNAL_ERROR` | サーバー内部エラー | 500 |

詳細は [docs/api.md](./docs/api.md) を参照。

</details>

---

## 設計で意識したこと

- **署名付きURLの保存先パスはクライアントに送らせない**
  - ログイン中ユーザーのJWTから`sub`を取り出し、サーバー側（Lambda）でS3キーを組み立てる
  - クライアントが指定したパスをそのまま信用すると、他人のファイルを上書き・閲覧できてしまうため
  - 詳細：[docs/architecture.md 4-2](./docs/architecture.md)
- **S3のアップロードイベントは「最低1回配信」を前提に、べき等性を設計する**
  - `upload_audit_log`テーブルの`file_key`にUNIQUE制約を張る
  - `processing`状態での予約INSERTを「一番最初に成功した呼び出しだけが処理を進めてよい」関所にする
  - これにより、重複配信による二重集計を防いでいる
  - 詳細：[docs/database.md 2-3](./docs/database.md)
- **Cognitoを使わず、GoogleのIDトークンをLambda AuthorizerでJWKS検証する**
  - 個人のGoogleアカウント1つでログインできればよいという要件に対し、Cognitoの複数IdP対応・ユーザー管理UI等は過剰装備と判断
  - OIDCの検証ロジック自体を理解する目的も兼ねて自前実装にした
  - 詳細：[docs/architecture.md 7-4](./docs/architecture.md)
- **JWT検証をLambda Authorizer（VPC外）に切り出す**
  - RDS接続用のsummary用LambdaはVPC内に置く必要があるが、VPC内からはGoogleのJWKSエンドポイント（インターネット）に到達できずタイムアウトする
  - 検証だけを担当するVPC外のLambda Authorizerを手前に置くことで解消した
- **集計はアップロード時に1回だけ行い、画面はRDSを読むだけにする**
  - Amazon Athenaで都度スキャンする案も検討した
  - 画面を開くたびに課金・レイテンシが発生する構成は要件（集計結果の一覧表示）に対して過剰と判断した
  - 詳細：[docs/architecture.md 7-1](./docs/architecture.md)
- **セキュリティレビューを実装前に自分で実施**
  - 署名付きURLのパス偽装・SQLインジェクション・認証情報の管理方法など8件の指摘を洗い出した
  - 設計に反映してから実装に着手した
  - 詳細：[docs/security.md](./docs/security.md)

---

## ディレクトリ構成

```
csv-data-pipeline/
  backend/       # Lambda（署名付きURL発行・CSV取込・集計API）、Fargate（バックフィル）
  frontend/      # React + Vite（ログイン・アップロード・集計結果表の3画面）
  docs/          # このリポジトリの設計ドキュメント（要件定義・アーキテクチャ・DB・API・セキュリティ）
```

- `backend/`の動かし方は [backend/README.md](./backend/README.md)
- `frontend/`の動かし方は [frontend/README.md](./frontend/README.md)

## ドキュメント一覧

| ドキュメント | 内容 |
|---|---|
| [docs/requirements.md](./docs/requirements.md) | 要件定義書 |
| [docs/architecture.md](./docs/architecture.md) | アーキテクチャ設計書（構成・セキュリティ設計・技術選定の比較検討） |
| [docs/database.md](./docs/database.md) | データベース設計（DDL・UPSERT・べき等性） |
| [docs/api.md](./docs/api.md) | API仕様書 |
| [docs/csv-format.md](./docs/csv-format.md) | 取込CSVフォーマット仕様 |
| [docs/network.md](./docs/network.md) | ネットワーク設計（VPC・サブネット・SG） |
| [docs/security.md](./docs/security.md) | セキュリティレビュー記録 |
| [docs/deploy.md](./docs/deploy.md) | デプロイ手順（フロントエンド・Lambda・インフラ） |
