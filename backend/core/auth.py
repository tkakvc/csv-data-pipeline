"""GoogleのIDトークン（OIDC）を検証するモジュール。

Cognitoは使わず、Lambda Authorizerで自前検証する方針に対応する。
"""

from google.auth.transport import requests as google_requests
from google.oauth2 import id_token

# google-authライブラリが内部でGoogleのJWKSエンドポイントを取得・キャッシュする。
# モジュールレベルで1つだけ生成し、Lambdaのウォームスタート間で使い回す。
_request = google_requests.Request()


def verify_google_id_token(token: str, client_id: str) -> dict:
    """GoogleのIDトークンを検証し、claims（sub, email等）を返す。

    署名・有効期限・issuer（iss）・audience（aud）を検証する。
    無効なトークンの場合は google.auth.exceptions.GoogleAuthError（ValueErrorのサブクラス）を送出する。
    """
    # id_token.verify_oauth2_token が、Googleの公開鍵(JWKS)を使って署名を検証し、
    # 問題なければJWTのペイロード（claims、＝subやemailなどの情報）を辞書として返す。
    # 署名が不正・期限切れ・client_id（aud）が違う、などの場合はここで例外が発生する。
    return id_token.verify_oauth2_token(token, _request, client_id)


def extract_bearer_token(headers: dict) -> str:
    """API Gatewayのheadersから 'Authorization: Bearer <token>' の <token> 部分を取り出す。

    ヘッダー名の大文字・小文字はHTTPの仕様上どちらでも良いため、比較前に正規化する。
    """
    # {k.lower(): v for k, v in ...} は「辞書内包表記」というPythonの書き方。
    # 元の辞書のキーを全部小文字にした、新しい辞書を作っている。
    # 例：{"Authorization": "Bearer xxx"} → {"authorization": "Bearer xxx"}
    normalized = {k.lower(): v for k, v in (headers or {}).items()}
    auth_header = normalized.get("authorization")

    # ヘッダーが無い、または "Bearer " から始まっていなければ不正なリクエストとして例外を投げる
    if not auth_header or not auth_header.startswith("Bearer "):
        raise ValueError("Authorization header missing or malformed")

    # "Bearer " という接頭辞（7文字）を取り除いた残りの部分（実際のトークン文字列）を返す
    return auth_header[len("Bearer "):]
