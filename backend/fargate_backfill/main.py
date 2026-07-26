"""⑧ バックフィルFargateタスク。

`aws ecs run-task` で手動起動する
（EventBridgeは経由しない。振り分け先がFargateタスク1つだけのため、挟むメリットが無く不採用）。
"""

import logging
import os

# Dockerfileでcore/をmain.pyと同じ階層(/app)にコピーするため、素直にimportできる
# （ローカルで直接実行する場合は、backend/をカレントディレクトリにするか PYTHONPATH に加えること）。
from core import db, repository

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("backfill")


def main() -> None:
    """このタスクのエントリーポイント（一番最初に実行される処理）。"""
    # 環境変数TARGET_USER_SUBが指定されていればそのユーザーだけ、
    # 指定が無ければ全ユーザーを対象にする
    target_sub = os.environ.get("TARGET_USER_SUB")  # 未指定なら全ユーザー対象
    conn = db.get_connection()

    # target_subがあれば1件だけのリスト、無ければDBから全ユーザーのsub一覧を取得する
    # ("[target_sub] if target_sub else ..." は「条件式」というPythonの書き方。
    #  target_subが真（＝Noneでも空文字でもない）ならtarget_subだけのリスト、
    #  そうでなければelse以降の値、を選ぶ)
    subs = [target_sub] if target_sub else repository.fetch_all_user_subs(conn)

    if not subs:
        logger.info("対象ユーザーが0件のため、何も行わずに終了します")
        return

    # 対象ユーザーを1人ずつ処理する
    for sub in subs:
        repository.rebuild_summary_for_user(conn, sub)
        logger.info("rebuilt summary for user_sub=%s", sub)

    logger.info("backfill completed for %d user(s)", len(subs))


# このファイルが「直接実行」された場合だけmain()を呼ぶ、というPythonの慣習的な書き方。
# （他のファイルからimportされただけのときはmain()は自動実行されない）
if __name__ == "__main__":
    main()
