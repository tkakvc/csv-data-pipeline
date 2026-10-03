"""API GatewayのLambda Authorizer（REQUEST型・HTTP API）。

presign・summary両ルートの手前でJWT検証だけを行う。このLambdaはVPCに入れない
（Googleのjwksエンドポイントにインターネット経由でアクセスする必要があるため）。
summary用Lambdaのように検証ロジックを自前で持たせると、RDS接続用にVPCへ入れた瞬間、
インターネットへ出られなくなりGoogleへの問い合わせがタイムアウトする、という問題が起きる
（詳細はdocs/architecture.md参照）。それを避けるため、検証だけをこの専用Lambdaに切り出す。
"""

import os

from core.auth import extract_bearer_token, verify_google_id_token

GOOGLE_OAUTH_CLIENT_ID = os.environ["GOOGLE_OAUTH_CLIENT_ID"]


def handler(event, context):
    """API Gatewayから呼ばれるエントリーポイント。

    戻り値の形式（HTTP APIのシンプルレスポンス）：
      { "isAuthorized": bool, "context": {...} }
    isAuthorized=Falseの場合、API Gatewayはこの先のLambda（presign・summary）を呼ばず、
    ブラウザに401を返す。isAuthorized=Trueの場合、contextの中身がそのまま、
    呼び出し先Lambdaのevent["requestContext"]["authorizer"]["lambda"]として渡される。
    """
    try:
        token = extract_bearer_token(event.get("headers", {}))
        claims = verify_google_id_token(token, GOOGLE_OAUTH_CLIENT_ID)
    except Exception:
        return {"isAuthorized": False}

    # subだけを次のLambdaに引き継ぐ（他のclaims、例えばemailは今回使わないので渡さない）
    return {"isAuthorized": True, "context": {"sub": claims["sub"]}}
