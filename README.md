# csv-data-pipeline

CSVでアップロードされた経費データをAWS上で取り込み・集計するデータパイプライン。
S3・Lambda・RDS(PostgreSQL)・ECS Fargateを中心に、AWSインフラ設計とデータパイプライン構築に重点を置いたポートフォリオ。

## 構成

- `backend/` — CSV取込・署名付きURL発行・集計取得の3Lambdaと、バックフィル用Fargateタスク
