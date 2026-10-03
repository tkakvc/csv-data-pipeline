"""API GatewayのLambda Authorizer（REQUEST型・HTTP API）。

presign・summary両ルートの手前でJWT検証だけを行う。このLambdaはVPCに入れない
（GoogleのJWKSエンドポイントにインターネット経由でアクセスする必要があるため。
summary用LambdaをVPC内に置いた結果、JWKS取得がタイムアウトする問題が起きたため、
検証だけをこの専用Lambdaに切り出した）。
"""

import os

from core.auth import extract_bearer_token, verify_google_id_token

GOOGLE_OAUTH_CLIENT_ID = os.environ["GOOGLE_OAUTH_CLIENT_ID"]


def handler(event, context):
    """戻り値はHTTP APIのシンプルレスポンス形式：{ "isAuthorized": bool, "context": {...} }。
    isAuthorized=Trueの場合、contextの中身がそのまま呼び出し先Lambdaの
    event["requestContext"]["authorizer"]["lambda"]として渡される。
    """
    try:
        token = extract_bearer_token(event.get("headers", {}))
        claims = verify_google_id_token(token, GOOGLE_OAUTH_CLIENT_ID)
    except Exception:
        return {"isAuthorized": False}

    return {"isAuthorized": True, "context": {"sub": claims["sub"]}}
