"""GoogleのIDトークン（OIDC）を検証するモジュール。

Cognitoは使わず、Lambda Authorizerで自前検証する方針に対応する。
"""

from google.auth.transport import requests as google_requests
from google.oauth2 import id_token

# JWKSエンドポイントの取得・キャッシュはこのRequestオブジェクトが内部で行うため、
# モジュールレベルで1つだけ生成し、Lambdaのウォームスタート間で使い回す。
_request = google_requests.Request()


def verify_google_id_token(token: str, client_id: str) -> dict:
    """GoogleのIDトークンを検証し、claims（sub, email等）を返す。

    署名・有効期限・issuer（iss）・audience（aud）を検証する。
    無効なトークンの場合は google.auth.exceptions.GoogleAuthError（ValueErrorのサブクラス）を送出する。
    """
    return id_token.verify_oauth2_token(token, _request, client_id)


def extract_bearer_token(headers: dict) -> str:
    """API Gatewayのheadersから 'Authorization: Bearer <token>' の <token> 部分を取り出す。

    ヘッダー名の大文字・小文字はHTTPの仕様上どちらでも良いため、比較前に正規化する。
    """
    normalized = {k.lower(): v for k, v in (headers or {}).items()}
    auth_header = normalized.get("authorization")

    if not auth_header or not auth_header.startswith("Bearer "):
        raise ValueError("Authorization header missing or malformed")

    return auth_header[len("Bearer "):]
