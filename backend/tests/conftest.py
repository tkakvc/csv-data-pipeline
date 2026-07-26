"""
一部のLambdaハンドラーはモジュール読み込み時（importした瞬間）に
os.environ[...]で必須の環境変数を読む・boto3クライアントを作るため、
テスト実行環境にもダミー値を設定しておく必要がある（本物のAWS/Googleには繋がない。
値の中身が使われるのはimportではなく実際に関数を呼んだ時なので、ダミーで問題ない）。
"""

import os

os.environ.setdefault("AWS_DEFAULT_REGION", "ap-northeast-1")
os.environ.setdefault("UPLOAD_BUCKET_NAME", "dummy-bucket-for-tests")
os.environ.setdefault("GOOGLE_OAUTH_CLIENT_ID", "dummy-client-id-for-tests")
