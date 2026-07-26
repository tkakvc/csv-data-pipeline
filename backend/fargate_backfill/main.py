"""⑧ バックフィルFargateタスク。

`aws ecs run-task` で手動起動する
（EventBridgeは経由しない。振り分け先がFargateタスク1つだけのため、挟むメリットが無く不採用）。
"""

import logging
import os

# ローカルで直接実行する場合は、backend/をカレントディレクトリにするか PYTHONPATH に加えること。
from core import db, repository

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("backfill")


def main() -> None:
    """このタスクのエントリーポイント。"""
    target_sub = os.environ.get("TARGET_USER_SUB")  # 未指定なら全ユーザー対象
    conn = db.get_connection()

    subs = [target_sub] if target_sub else repository.fetch_all_user_subs(conn)

    if not subs:
        logger.info("対象ユーザーが0件のため、何も行わずに終了します")
        return

    for sub in subs:
        repository.rebuild_summary_for_user(conn, sub)
        logger.info("rebuilt summary for user_sub=%s", sub)

    logger.info("backfill completed for %d user(s)", len(subs))


if __name__ == "__main__":
    main()
