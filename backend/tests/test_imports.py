"""
全モジュールが依存パッケージ不足なしでimportできるかだけを確認するスモークテスト。
ロジックの正しさは検証しない（それはtest_csv_parser.py・test_ingest.pyの役割）。
requirements.txtの記載漏れ（例：google-authはrequestsを自動では連れてこない）を
ローカルで即座に検知するためのもの。
"""

import importlib

import pytest

MODULES = [
    "core.auth",
    "core.csv_parser",
    "core.db",
    "core.repository",
    "lambda_presign.handler",
    "lambda_ingest.handler",
    "lambda_summary.handler",
    "fargate_backfill.main",
]


@pytest.mark.parametrize("module_name", MODULES)
def test_module_imports_without_error(module_name):
    importlib.import_module(module_name)
