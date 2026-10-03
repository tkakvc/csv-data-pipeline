# デプロイ手順

- 自動デプロイ（CI/CD）は組んでいない（[requirements.md](./requirements.md) 6章「個人開発・学習目的のため、CI/CDの厳格な運用までは求めない」）。コードを直した後、以下の手順を手動で実行する必要がある

---

## 1. フロントエンドを直した場合

`frontend/src/`配下を変更したら、ビルドしてS3に反映し、CloudFrontのキャッシュを更新する。

```bash
cd frontend
npm run build
aws s3 sync dist/ s3://cost-csv-frontend-store-460677238703-ap-northeast-1/ --region ap-northeast-1 --delete
aws cloudfront create-invalidation --distribution-id E19ZF40NXY41U6 --paths "/*"
```

- `npm run build`：`frontend/src/`のReactコードを、ブラウザで動く静的ファイル（`dist/`配下のHTML/JS/CSS）にビルドする
- `aws s3 sync`：`dist/`の中身を、本番で使っているS3バケットにアップロードする。`--delete`を付けることで、前回ビルドの古いファイル（ファイル名にハッシュが含まれるため、ビルドのたびに名前が変わる）も削除する
- `aws cloudfront create-invalidation`：CloudFrontに溜まっている古いキャッシュを無効化し、次のアクセスから新しいファイルが配信されるようにする

## 2. Lambdaのコード（`backend/`）を直した場合

```bash
cd backend
bash build.sh
```

で各Lambda用のzipを作り直した後、`infra/envs/dev`で`terraform apply`を実行する（`source_code_hash`の変化をTerraformが検知し、該当Lambdaのコードだけが更新される）。

## 3. インフラ構成（`infra/`配下の`.tf`ファイル）を直した場合

```bash
cd infra/envs/dev
terraform plan -out=xxx.tfplan
terraform apply "xxx.tfplan"
```
