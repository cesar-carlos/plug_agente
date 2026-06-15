#!/usr/bin/env python3
"""One-shot path updates after tool/ folder reorganization."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

REPLACEMENTS: list[tuple[str, str]] = [
    # Manifests (before generic tool/ paths)
    ("tool/agent_actions/manifests/agent_actions_contract_test_paths.txt", "tool/agent_actions/manifests/agent_actions_contract_test_paths.txt"),
    ("tool/agent_actions/manifests/agent_actions_ui_test_paths.txt", "tool/agent_actions/manifests/agent_actions_ui_test_paths.txt"),
    ("tool/benchmarks/manifests/odbc_result_encoding_benchmark_test_paths.txt", "tool/benchmarks/manifests/odbc_result_encoding_benchmark_test_paths.txt"),
    # Agent actions
    ("tool/agent_actions/agent_action_security_gate_checklist.dart", "tool/agent_actions/agent_action_security_gate_checklist.dart"),
    ("tool/agent_actions/homologate_hub_agent_actions.py", "tool/agent_actions/homologate_hub_agent_actions.py"),
    ("tool/agent_actions/preflight_agent_actions_production.dart", "tool/agent_actions/preflight_agent_actions_production.dart"),
    ("tool/agent_actions/preflight_agent_actions_production.py", "tool/agent_actions/preflight_agent_actions_production.py"),
    ("tool/agent_actions/restore_agent_action_editor.py", "tool/agent_actions/restore_agent_action_editor.py"),
    ("tool/agent_actions/run_agent_actions_operational_gate.py", "tool/agent_actions/run_agent_actions_operational_gate.py"),
    ("tool/agent_actions/split_agent_action_editor.py", "tool/agent_actions/split_agent_action_editor.py"),
    # Appcast
    ("tool/appcast/appcast_manager.py", "tool/appcast/appcast_manager.py"),
    ("tool/appcast/appcast_signing.py", "tool/appcast/appcast_signing.py"),
    ("tool/appcast/generate_appcast_signing_key.py", "tool/appcast/generate_appcast_signing_key.py"),
    ("tool/appcast/test_appcast_manager.py", "tool/appcast/test_appcast_manager.py"),
    ("tool/appcast/test_appcast_signing.py", "tool/appcast/test_appcast_signing.py"),
    ("tool/appcast/validate_launcher_status.py", "tool/appcast/validate_launcher_status.py"),
    ("tool/appcast/test_validate_launcher_status.py", "tool/appcast/test_validate_launcher_status.py"),
    ("tool/appcast/validate_release.py", "tool/appcast/validate_release.py"),
    ("tool/appcast/test_validate_release.py", "tool/appcast/test_validate_release.py"),
    # Benchmarks
    ("tool/benchmarks/benchmark_evolution_report.py", "tool/benchmarks/benchmark_evolution_report.py"),
    ("tool/benchmarks/benchmark_odbc_gateway_encoding.dart", "tool/benchmarks/benchmark_odbc_gateway_encoding.dart"),
    ("tool/benchmarks/benchmark_odbc_pool_modes.dart", "tool/benchmarks/benchmark_odbc_pool_modes.dart"),
    ("tool/benchmarks/benchmark_transport_pipeline.dart", "tool/benchmarks/benchmark_transport_pipeline.dart"),
    ("tool/benchmarks/benchmark_transport_pipeline_async_impl.dart", "tool/benchmarks/benchmark_transport_pipeline_async_impl.dart"),
    ("tool/benchmarks/benchmark_transport_pipeline_async_stub.dart", "tool/benchmarks/benchmark_transport_pipeline_async_stub.dart"),
    ("tool/benchmarks/compare_benchmark_summary.py", "tool/benchmarks/compare_benchmark_summary.py"),
    ("tool/benchmarks/migrate_benchmark_logs.py", "tool/benchmarks/migrate_benchmark_logs.py"),
    ("tool/benchmarks/promote_benchmark_baseline.py", "tool/benchmarks/promote_benchmark_baseline.py"),
    ("tool/benchmarks/run_benchmark_suite.py", "tool/benchmarks/run_benchmark_suite.py"),
    ("tool/benchmarks/odbc_async_benchmark.py", "tool/benchmarks/odbc_async_benchmark.py"),
    ("tool/benchmarks/odbc_driver_matrix_benchmark.py", "tool/benchmarks/odbc_driver_matrix_benchmark.py"),
    ("tool/benchmarks/odbc_streaming_benchmark.py", "tool/benchmarks/odbc_streaming_benchmark.py"),
    ("tool/benchmarks/run_odbc_result_encoding_benchmark.ps1", "tool/benchmarks/run_odbc_result_encoding_benchmark.ps1"),
    # E2E
    ("tool/e2e/check_e2e_env.dart", "tool/e2e/check_e2e_env.dart"),
    ("tool/e2e/export_e2e_secrets_from_local.dart", "tool/e2e/export_e2e_secrets_from_local.dart"),
    ("tool/e2e/fetch_e2e_hub_token_from_local_config.dart", "tool/e2e/fetch_e2e_hub_token_from_local_config.dart"),
    ("tool/e2e/generate_dev_e2e_signing.dart", "tool/e2e/generate_dev_e2e_signing.dart"),
    ("tool/e2e/promote_e2e_signing_from_monorepo_env.dart", "tool/e2e/promote_e2e_signing_from_monorepo_env.dart"),
    ("tool/e2e/suggest_e2e_hub_from_local_config.dart", "tool/e2e/suggest_e2e_hub_from_local_config.dart"),
    ("tool/e2e/sync_e2e_hub_env_from_local.dart", "tool/e2e/sync_e2e_hub_env_from_local.dart"),
    ("tool/e2e/validate_live_hub_agent_actions_env.dart", "tool/e2e/validate_live_hub_agent_actions_env.dart"),
    # Elevated
    ("tool/elevated/build_elevated_runner.py", "tool/elevated/build_elevated_runner.py"),
    ("tool/elevated/homologate_elevated_runner.py", "tool/elevated/homologate_elevated_runner.py"),
    # ODBC
    ("tool/odbc/check_odbc_fast_runtime.dart", "tool/odbc/check_odbc_fast_runtime.dart"),
    ("tool/odbc/export_odbc_health_snapshot_template.dart", "tool/odbc/export_odbc_health_snapshot_template.dart"),
    ("tool/odbc/run_odbc_operational_validation.py", "tool/odbc/run_odbc_operational_validation.py"),
    ("tool/odbc/run_odbc_release_gate.py", "tool/odbc/run_odbc_release_gate.py"),
    ("tool/odbc/test_db_connection.dart", "tool/odbc/test_db_connection.dart"),
    # Release
    ("tool/release/pre_publish_release.py", "tool/release/pre_publish_release.py"),
    ("tool/release/pre_release_checklist.ps1", "tool/release/pre_release_checklist.ps1"),
    ("tool/release/release_preflight.py", "tool/release/release_preflight.py"),
    ("tool/release/run_stress_baseline.ps1", "tool/release/run_stress_baseline.ps1"),
    ("tool/release/test_release_preflight.py", "tool/release/test_release_preflight.py"),
    # Dev
    ("tool/dev/check_lib_file_limits.dart", "tool/dev/check_lib_file_limits.dart"),
    ("tool/dev/check_startup_minimized_readiness.dart", "tool/dev/check_startup_minimized_readiness.dart"),
    ("tool/dev/install_git_hooks.py", "tool/dev/install_git_hooks.py"),
    ("tool/dev/list_plug_agente_secure_storage_keys.dart", "tool/dev/list_plug_agente_secure_storage_keys.dart"),
    ("tool/dev/merge_l10n_arb.py", "tool/dev/merge_l10n_arb.py"),
    # Fixtures
    ("tool/fixtures/select1.sql", "tool/fixtures/select1.sql"),
    ("tool/fixtures/test_db_cmd.bat", "tool/fixtures/test_db_cmd.bat"),
    ("tool/fixtures/test_select1_cmd.bat", "tool/fixtures/test_select1_cmd.bat"),
    # Python imports
    ("from tool.benchmarks.compare_benchmark_summary", "from tool.benchmarks.compare_benchmark_summary"),
    ("from tool.benchmarks.run_benchmark_suite", "from tool.benchmarks.run_benchmark_suite"),
    ("from tool.benchmarks.migrate_benchmark_logs", "from tool.benchmarks.migrate_benchmark_logs"),
    ("from tool.benchmarks.promote_benchmark_baseline", "from tool.benchmarks.promote_benchmark_baseline"),
    ("from tool.benchmarks.benchmark_evolution_report", "from tool.benchmarks.benchmark_evolution_report"),
    ("from tool.appcast.appcast_signing", "from tool.appcast.appcast_signing"),
    # unittest module paths
    ("tool.appcast.test_appcast_manager", "tool.appcast.test_appcast_manager"),
    ("tool.appcast.test_validate_release", "tool.appcast.test_validate_release"),
    # githooks regex
    ("tool/release_preflight\\.py|tool/pre_publish_release\\.py", "tool/release/release_preflight.py|tool/release/pre_publish_release.py"),
]

SKIP_DIRS = {
    ".git",
    ".dart_tool",
    "build",
    "node_modules",
    "__pycache__",
}

SKIP_SUFFIXES = {".pyc", ".dll", ".snapshot", ".lock", ".dill"}


def should_process(path: Path) -> bool:
    if any(part in SKIP_DIRS for part in path.parts):
        return False
    if path.suffix in SKIP_SUFFIXES:
        return False
    return path.is_file()


def update_file(path: Path) -> bool:
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return False

    original = text
    for old, new in REPLACEMENTS:
        text = text.replace(old, new)

    if text != original:
        path.write_text(text, encoding="utf-8", newline="\n")
        return True
    return False


def patch_dart_src_imports(path: Path) -> bool:
    if path.suffix != ".dart":
        return False
    if path.parent.name not in {"agent_actions", "benchmarks", "e2e", "odbc", "dev"}:
        return False
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return False
    updated = re.sub(r"import 'src/", "import '../src/", text)
    if updated != text:
        path.write_text(updated, encoding="utf-8", newline="\n")
        return True
    return False


BOOTSTRAP_SNIPPET = """import sys
from pathlib import Path

_TOOL_DIR = Path(__file__).resolve().parents[1]
_ROOT = _TOOL_DIR.parent
for _entry in (str(_ROOT), str(_TOOL_DIR)):
    if _entry not in sys.path:
        sys.path.insert(0, _entry)

"""

CATEGORY_PY_DIRS = [
    "agent_actions",
    "appcast",
    "benchmarks",
    "e2e",
    "elevated",
    "odbc",
    "release",
    "dev",
]


def patch_python_bootstrap(path: Path) -> bool:
    if path.suffix != ".py" or path.name == "__init__.py":
        return False
    if path.parent.name not in CATEGORY_PY_DIRS:
        return False
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return False
    if "_TOOL_DIR = Path(__file__).resolve().parents[1]" in text:
        return False
    if not text.startswith("#!/usr/bin/env python3"):
        return False

  # Insert after shebang and future imports
    lines = text.splitlines(keepends=True)
    insert_at = 0
    if lines and lines[0].startswith("#!"):
        insert_at = 1
    while insert_at < len(lines) and (
        lines[insert_at].strip() == ""
        or lines[insert_at].startswith('"""')
        or lines[insert_at].startswith("'''")
        or "from __future__" in lines[insert_at]
    ):
        if '"""' in lines[insert_at] or "'''" in lines[insert_at]:
            insert_at += 1
            while insert_at < len(lines) and '"""' not in lines[insert_at] and "'''" not in lines[insert_at]:
                insert_at += 1
            insert_at += 1
            continue
        insert_at += 1

    new_text = "".join(lines[:insert_at]) + "\n" + BOOTSTRAP_SNIPPET + "".join(lines[insert_at:])
    path.write_text(new_text, encoding="utf-8", newline="\n")
    return True


def fix_benchmark_sys_path(path: Path) -> bool:
    if path.name not in {
        "run_benchmark_suite.py",
        "odbc_async_benchmark.py",
        "odbc_streaming_benchmark.py",
        "run_odbc_release_gate.py",
        "compare_benchmark_summary.py",
        "migrate_benchmark_logs.py",
        "promote_benchmark_baseline.py",
        "benchmark_evolution_report.py",
        "generate_appcast_signing_key.py",
    }:
        return False
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return False
    updated = text.replace(
        'sys.path.insert(0, str(Path(__file__).resolve().parent.parent))',
        'sys.path.insert(0, str(Path(__file__).resolve().parents[2]))',
    )
    if updated != text:
        path.write_text(updated, encoding="utf-8", newline="\n")
        return True
    return False


def main() -> None:
    changed: list[str] = []
    for path in ROOT.rglob("*"):
        if not should_process(path):
            continue
        flags = (
            update_file(path),
            patch_dart_src_imports(path),
            patch_python_bootstrap(path),
            fix_benchmark_sys_path(path),
        )
        if any(flags):
            changed.append(str(path.relative_to(ROOT)))

    print(f"Updated {len(changed)} files")
    for item in sorted(changed)[:80]:
        print(f"  {item}")
    if len(changed) > 80:
        print(f"  ... and {len(changed) - 80} more")


if __name__ == "__main__":
    main()
