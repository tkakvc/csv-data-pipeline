# アーキテクチャ設計書

- 関連ドキュメント：要件は [requirements.md](./requirements.md)、セキュリティ対策は [security.md](./security.md)、DB設計は [database.md](./database.md)、API仕様は [api.md](./api.md)

---

## 1. システム構成

### 1-1 メインフロー

```
①CSVアップロード画面
      │ ⓪ 署名付きURL発行API（API Gateway + Lambda）に「アップロードしたい」とリクエスト
      │ ← 署名付きURLを受け取る
      │ 受け取った署名付きURLでS3へ直接PUT
      ▼
②S3（CSV保存用バケット）
      │ アップロードを検知 → Lambdaを直接呼び出す（EventBridgeは経由しない）
      ▼
④CSV取込Lambda
      │ CSVを解析・バリデーション
      │ → 生データテーブルにINSERT
      │ → 集計してsummaryテーブルにINSERT/UPSERT
      │ → 誰が・いつアップロードしたかを監査ログとして記録
      ▼
⑤RDS（PostgreSQL）
      ├── raw テーブル（生データ）
      └── summary テーブル（集計済みデータ）
      ▲
      │ 読み取りAPIが参照
⑥API Gateway + Lambda（読み取り専用API）
      ▲
      │ 呼び出し
⑦集計結果表画面
```

- ⓪と⑥はどちらも「API Gateway + Lambda」という同じ仕組みを使うが、役割が異なる
  - ⓪：ファイルがS3に置かれる**前**に1回だけ動く、署名付きURLを発行するだけの軽い処理
  - ④：ファイルがS3に置かれた**後**に動く、CSVを解析してDBに書き込む処理

### 1-2 バックフィルフロー（管理者が手動で実行）

```
管理者がAWS CLIで `aws ecs run-task` を実行
      ▼
⑧ECS Fargateタスク（バックフィル専用）
      │ rawテーブルを全件読み直す
      │ 最新の集計ロジックでsummaryテーブルを作り直す
      ▼
⑤RDS（summaryテーブルを更新）
```

- 目的・トリガーの詳細は6章「バックフィル機能」を参照

---

## 2. コンポーネント一覧

| サービス | 役割 |
|---|---|
| S3 | CSV保存・フロントエンド静的ホスティング |
| CSV取込Lambda | S3のアップロードイベントを直接受け取り、CSV解析・DB書き込み・監査ログ記録を行う |
| ECS Fargate + ECR | バックフィル（過去データの再集計）専用。通常のCSV取込には使わない |
| RDS (PostgreSQL) | 生データ・集計データの保存 |
| API Gateway + Lambda（読み取り用） | 集計結果を返す読み取り専用API |
| API Gateway + Lambda（署名付きURL発行用） | CSVアップロード用の署名付きURLを発行するAPI |
| CloudFront | フロントエンド配信 |
| Google OIDC（Lambda Authorizerで自前検証） | OIDCによるログイン（個人のGoogleアカウントでログイン） |
| Secrets Manager | RDSの認証情報を安全に保管・取得する |
| IAM | Lambda実行ロール・Fargateタスクロール（バックフィル用） |

---

## 3. データベース設計（概要）

```
raw_expenses（生データテーブル）
  id, uploaded_at, 元CSVの各列...

summary_expenses（集計テーブル）
  id, 集計キー（月・部門・勘定科目）, 集計値, updated_at

upload_audit_log（アップロード監査ログ）
  id, user_sub, file_key, status, processed_at
```

詳細なDDL・UPSERT/バックフィルのSQL・べき等性の実装は [database.md](./database.md) を参照。

---

## 4. セキュリティ設計

事前に洗い出したセキュリティレビューの指摘（[security.md](./security.md)）への対応方針。

### 4-1 認証方式

- OIDC（OpenID Connect）による「Googleでログイン」
- ログイン後にGoogle側から発行されるIDトークン（JWT）を、⓪・⑥それぞれのAPI Gatewayに設定したLambda Authorizerが検証する
- Lambda Authorizerは、GoogleのJWKS（JSON Web Key Set）エンドポイントから公開鍵を取得し、JWTの署名・発行者（iss）・宛先（aud）を自前で検証する
- Cognitoは使わない（比較は7-4）

### 4-2 署名付きURLの保存先パスの決め方

- 採用しない実装：クライアントが「このファイル名で発行して」と指定した値をそのまま使う
- 採用する実装：保存先パスは、JWTに含まれる`sub`（そのユーザーを一意に識別する不変の値）から、Lambda自身が組み立てる

```
ブラウザ → Lambda：「アップロードしたい」（保存先パスは送らない）
Lambda：JWTを検証 → sub=xxxxx を取り出す
       → uploads/xxxxx/2026-07-20_costs.csv というパスでURLを発行
```

### 4-3 SQL実行方式

- CSV取込Lambda内のCSV→SQL変換処理は、パラメータ化クエリを使用する
- CSVの値を文字列連結でSQL文に組み込むことを禁止する
- バックフィルFargateタスクも、CSV取込Lambdaと共通のPythonロジック（8章）を使うため、同じ方式が適用される

### 4-4 DB認証情報の管理

- RDSの接続パスワードはAWS Secrets Managerに保管する
- CSV取込Lambda・バックフィルFargateタスクは、いずれも起動時にSecrets Manager経由で認証情報を取得する

### 4-5 S3バケットの基本設定

- パブリックアクセスブロックを有効化
- サーバー側の保存時暗号化（SSE-S3）を有効化
- バージョニングを有効化（誤ってオブジェクトを削除した場合の復元用）

### 4-6 署名付きURLの有効期限

- 有効期限は実際のアップロードに必要な最短時間に絞る（300秒）

### 4-7 アップロードファイルの検証

- ファイルサイズの上限を設定する（10MB）
- 拡張子・Content-Typeがcsv以外のファイルは受け付けない
- CSV取込Lambda側でも、パースできない内容が来た場合は処理を中断し、raw/summaryテーブルへの書き込みを行わない

### 4-8 CORS設定

- S3バケットのCORS設定の`AllowedOrigins`は、フロントエンドのドメインのみを指定する（`*`は使用しない）

### 4-9 監査ログ

- CloudTrailでS3のデータイベント（PutObjectなど）のログを有効化する
- CSV取込Lambda自身も、処理の最後に「誰が・いつ・どのファイルを」取り込んだかを記録する

---

## 5. API設計（概要）

| API | メソッド・パス | 認証 | 概要 |
|---|---|---|---|
| 署名付きURL発行API | `POST /upload-url` | 必須 | CSVアップロード用のS3署名付きURLを発行する |
| 読み取り専用API | `GET /summary` | 必須 | 集計結果を取得する |

詳細なリクエスト・レスポンス、エラーコード一覧は [api.md](./api.md) を参照。

バックフィルの起動には専用のAPIを用意していない。管理者がAWS CLIで`aws ecs run-task`を手動実行する形にしている。要件（[requirements.md](./requirements.md)）で「夜間バッチは作らない」としており、自動化・専用画面を作るほどの頻度で使う機能ではないため。

---

## 6. バックフィル機能（過去データの再集計）

- 背景：集計ロジックに誤りが見つかり修正した場合、修正前にアップロード済みのCSVから作られたsummaryテーブルの値は自動的には直らない。rawテーブルには元データがそのまま残っているため、これを読み直して再集計すれば直せる
- 処理内容：rawテーブルを全件読み直し、最新の集計ロジックでsummaryテーブルを作り直す
- 実行方法：管理者がAWS CLIで`aws ecs run-task`を手動実行する
- なぜLambdaではなくFargateで作るか：全件処理のため、CSVの件数が多いとLambdaの最大実行時間（15分）を超える可能性がある。時間制限のないFargateを使う
- なぜEventBridgeを経由しないか：起動先がFargateタスク1つだけであり、複数の条件での振り分け・複数の宛先への配信というEventBridgeの得意分野が活きる場面がないため

---

## 7. 検討したが採用しなかった技術

技術選定の過程で比較した代替案と、不採用にした理由をまとめる。

### 7-1 Amazon Athena（S3上のファイルに直接SQLを投げるサービス）

CSVの生データをRDSに取り込まず、S3に置いたまま直接Athenaでクエリする案を検討した。

| 観点 | Athenaを使う場合 | 採用した方式（事前集計してRDSに保存） |
|---|---|---|
| 集計のタイミング | 集計結果表画面を開くたびに、S3上のCSVをスキャンして都度集計する | アップロード時（CSV取込Lambdaの実行時）に1回だけ集計を済ませ、結果をsummaryテーブルに保存する |
| 画面表示時の処理 | クエリを実行し、結果が返るまで数秒〜待つ | RDSへの単純なSELECT文だけで済む（ミリ秒オーダー） |
| 課金の単位 | クエリのたびに、スキャンしたデータ量に応じて課金される | 集計計算はアップロード時の1回だけ。画面を開く回数に依存しない |
| スキーマ管理 | Glue Data Catalogに別途登録・メンテナンスが必要 | RDSのテーブル定義がそのままスキーマになり、二重管理にならない |

判断の決め手：要件（FR-2）は「集計結果を一覧表示するだけ」であり、画面を開くたびに生データを再スキャンして集計し直す必要はない。加えてAthenaはクエリごとに1〜数秒のレイテンシがあり、`UPSERT`のような書き込みもできない。要件に合わない技術を「使ってみたいから」で組み込むと、技術選定の軸がぶれる（リソースドリブン開発）と考え、不採用にした。

### 7-2 CSV取込処理でのECS Fargate採用

CSV取込処理（S3アップロードごとに動くCSV解析・DB書き込み）を、Fargateにするか、Lambdaにするか比較した。

| 観点 | Fargate | Lambda（採用） |
|---|---|---|
| 処理時間 | 制限なし | 最大15分。今回の処理（数分で完了）には十分 |
| 起動速度 | コンテナイメージの取得・起動に数十秒かかることがある | 起動が速い |
| 運用の複雑さ | ECSクラスタ・タスク定義・サービスの管理が必要 | 管理する構成要素が少ない |
| コスト | NATゲートウェイが必要になるケースが多く高くつきやすい | 無料枠（月100万リクエスト・40万GB秒）内に収まりやすい |

結論：処理の性質（軽量・短時間・イベント駆動）がLambdaの得意分野に合致するため、Lambdaを採用した。

### 7-3 EventBridge（S3アップロード検知の仲介役としての採用）

S3のアップロード検知にEventBridgeを挟むか、S3から直接Lambdaを呼ぶかを検討した。S3の標準のイベント通知は直接呼び出せる対象が「Lambda」「SQS」「SNS」の3つに限られており、ECS Fargateタスクを直接起動できない。CSV取込処理をLambdaに決めた（7-2）ことで、S3から直接呼び出せるようになり、仲介役が不要になった。

結論：公開する構成ではEventBridgeを使わない。S3からLambdaを直接呼び出す。

### 7-4 Cognito（マネージド認証基盤）

Googleでログインする際、Cognito User Poolを挟んで認証を代行させるか、Googleが発行するIDトークンを直接検証するかを3案で比較した。

| 観点 | A案：Cognito・ネイティブ統合 | B案：Cognito・自前検証 | C案：Google直接・自前検証（採用） |
|---|---|---|---|
| JWT検証ロジックの実装経験 | 得られない（AWSが代行する） | 得られる | 得られる |
| 構築するAWSリソース | Cognito User Pool・Identity Provider・User Pool Client・Cognito Authorizerが必要 | 同左 | 不要（検証用Lambda Authorizer1つのみ） |
| 今回の要件との適合 | 過剰装備（複数IdP対応・MFA等、使わない機能が付いてくる） | 過剰装備（インフラ面は同上） | 要件にちょうど合う |

結論：C案を採用した。目的の1つが「OIDCのトークン検証ロジックを自分の手で理解し実装すること」であり、今回のユースケース（個人のGoogleアカウント1つでログイン）にはCognitoの追加機能（複数IdP対応・ユーザー管理UI・MFA等）は不要と判断した。

### 7-5 フロントエンドの配信方式（S3+CloudFront採用）

フロントエンド（React + TypeScript、Viteでビルド）を、S3+CloudFrontで静的配信するか、ECS Fargateでサーバーとして常時起動するかを検討した。

| 観点 | ECS Fargate（コンテナで常時起動） | S3+CloudFront（採用） |
|---|---|---|
| 必要性 | 動的なサーバー処理（SSR等）が無いため、コンテナを起動する理由が無い | ファイルをそのまま配るだけなので、S3で足りる |
| 課金 | アクセスの有無に関わらず、起動している間は常に課金される | 保存しているファイル容量に応じた課金のみ |
| HTTPS化 | ALB＋ACM証明書等が別途必要 | CloudFrontで完結する |

判断の決め手：Viteの出力にサーバー側処理が無い以上、Fargateの強み（時間のかかる処理・柔軟な実行環境）がフロントエンドには当てはまらない。加えてGoogle OAuthは本番運用時にHTTPSのオリジンしか許可しないため、CloudFrontによるHTTPS化はGoogleログイン機能自体の前提条件でもある。

---

## 8. 公開版と非公開の学習用実装（2トラック構成）

CSV取込処理について、公開するポートフォリオ本体と、実務の構成を再現する練習用実装を分けている。

| | 公開版（このリポジトリ） | 非公開版（実務の構成の再現、非公開） |
|---|---|---|
| CSV取込処理 | Lambda | ECS Fargate（ECRのPythonイメージ） |
| S3からのトリガー | Lambdaを直接呼び出す | EventBridge経由でFargateタスクを起動 |
| 採用理由 | 処理の性質（軽量・短時間）に合っているため（7-2） | 実務の構成をそのまま再現し、経験を保持するため |

- 共通化のポイント：CSV解析・バリデーション・集計のコアロジックはPythonの共通モジュール（`backend/core/`）として切り出し、Lambda用の薄いハンドラーと、非公開のFargate用の薄いエントリーポイントの両方から呼び出す構成にしている。実装の二重化を最小限に抑えるための設計判断
  ```
  backend/core/
    csv_parser.py            ← 共通ロジック（Lambda・非公開Fargateどちらも使う）
    db.py・repository.py・auth.py

  backend/lambda_ingest/handler.py            ← core/を呼ぶだけの薄いラッパー（公開版・Lambda用）
  infra-private/fargate_practice_app/main.py  ← core/を呼ぶだけの薄いラッパー（非公開版・Fargate用。.gitignoreで除外）
  ```
- 「なぜLambdaを選んだか」は7-2の要件との適合性に基づく客観的な判断であり、「実務ではFargate＋EventBridgeだった」という経験の保持は別軸の理由であることを、意図的に分けて整理している
