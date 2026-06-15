from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, Iterable, Mapping, Sequence

TOOL_DIR = Path(__file__).resolve().parent.parent
PROJECT_ROOT = TOOL_DIR.parent
AGENT_ACTIONS_MANIFESTS_DIR = TOOL_DIR / "agent_actions" / "manifests"
BENCHMARKS_MANIFESTS_DIR = TOOL_DIR / "benchmarks" / "manifests"


def ensure_utf8_stdio() -> None:
    """Avoid Windows cp1252 crashes when child tools emit non-ASCII log lines."""
    os.environ.setdefault("PYTHONIOENCODING", "utf-8")
    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if callable(reconfigure):
            reconfigure(encoding="utf-8", errors="replace")


def _emit_subprocess_line(line: str) -> None:
    try:
        print(line, end="")
    except UnicodeEncodeError:
        encoding = getattr(sys.stdout, "encoding", None) or "utf-8"
        print(line.encode(encoding, errors="replace").decode(encoding), end="")


class Console:
    CYAN = "\033[36m"
    GREEN = "\033[32m"
    YELLOW = "\033[33m"
    RED = "\033[31m"
    GRAY = "\033[90m"
    RESET = "\033[0m"

    @classmethod
    def _emit(cls, color: str, message: str) -> None:
        if sys.stdout.isatty():
            print(f"{color}{message}{cls.RESET}")
        else:
            print(message)

    @classmethod
    def step(cls, message: str) -> None:
        print()
        cls._emit(cls.CYAN, f"==> {message}")

    @classmethod
    def pass_(cls, message: str) -> None:
        cls._emit(cls.GREEN, f"  [ok] {message}")

    @classmethod
    def warn(cls, message: str) -> None:
        cls._emit(cls.YELLOW, f"  [warn] {message}")

    @classmethod
    def fail(cls, message: str) -> None:
        cls._emit(cls.RED, f"  [fail] {message}")

    @classmethod
    def hint(cls, message: str) -> None:
        cls._emit(cls.GRAY, f"  [hint] {message}")


def resolve_command(cmd: Sequence[str]) -> list[str]:
    args = list(cmd)
    if not args:
        raise RuntimeError("Command cannot be empty.")

    executable = args[0]
    resolved = shutil.which(executable) or executable
    if Path(resolved).suffix.lower() in {".bat", ".cmd"}:
        return ["cmd.exe", "/d", "/c", resolved, *args[1:]]
    return [resolved, *args[1:]]


def run(
    cmd: Sequence[str],
    *,
    cwd: Path | None = None,
    env: Mapping[str, str] | None = None,
    check: bool = True,
    capture: bool = False,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        resolve_command(cmd),
        cwd=cwd or PROJECT_ROOT,
        env=env,
        check=check,
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.STDOUT if capture else None,
    )


def run_streaming(
    cmd: Sequence[str],
    *,
    cwd: Path | None = None,
    env: Mapping[str, str] | None = None,
    log_path: Path | None = None,
) -> int:
    ensure_utf8_stdio()
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)

    with subprocess.Popen(
        resolve_command(cmd),
        cwd=cwd or PROJECT_ROOT,
        env=merged_env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
    ) as process:
        assert process.stdout is not None
        log_file = log_path.open("a", encoding="utf-8") if log_path else None
        try:
            for line in process.stdout:
                _emit_subprocess_line(line)
                if log_file is not None:
                    log_file.write(line)
        finally:
            if log_file is not None:
                log_file.close()
        return process.wait()


def import_dotenv_if_present(path: Path) -> None:
    if not path.is_file():
        return

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if not key:
            continue
        if not os.environ.get(key):
            os.environ[key] = value


def resolve_env_path(env_path: str | Path) -> Path:
    path = Path(env_path)
    if path.is_absolute():
        return path
    return PROJECT_ROOT / path


def get_effective_env_value(keys: Iterable[str]) -> str:
    for key in keys:
        value = os.environ.get(key)
        if value and value.strip():
            return value.strip()
    return ""


def get_git_commit_or_default() -> str:
    try:
        result = run(["git", "rev-parse", "--short", "HEAD"], capture=True, check=False)
        if result.returncode == 0 and result.stdout:
            commit = result.stdout.strip()
            if commit:
                return commit
    except (OSError, subprocess.SubprocessError):
        pass
    return "(not resolved)"


def read_manifest_test_paths(file_name: str) -> list[str]:
    manifest_path = AGENT_ACTIONS_MANIFESTS_DIR / file_name
    if not manifest_path.is_file():
        raise FileNotFoundError(f"Missing test manifest: {manifest_path}")

    paths: list[str] = []
    for raw_line in manifest_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if line and not line.startswith("#"):
            paths.append(line)
    return paths


def format_timestamp() -> str:
    return datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S %z")


def invoke_step(
    name: str,
    command: Callable[[], int],
    *,
    log_path: Path | None = None,
) -> tuple[bool, str, str]:
    Console.step(name)
    started_at = format_timestamp()
    if log_path is not None:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        if log_path.exists():
            log_path.unlink()
    exit_code = command()
    finished_at = format_timestamp()
    if exit_code != 0:
        Console.fail(f"{name} failed.")
        return False, started_at, finished_at
    Console.pass_(f"{name} completed.")
    return True, started_at, finished_at


def get_dsn_driver_family(connection_string: str) -> str:
    if not connection_string or connection_string == "(not configured)":
        return "(not configured)"

    upper = connection_string.upper()
    if "POSTGRE" in upper:
        return "PostgreSQL"
    if "ANYWHERE" in upper or "SYBASE" in upper or "SQLA" in upper:
        return "SQL Anywhere"
    if "SQL SERVER" in upper or "ODBC DRIVER" in upper or "NATIVE CLIENT" in upper:
        return "SQL Server"
    return "unknown"


def get_native_adaptive_eligibility(driver_family: str) -> str:
    if driver_family in {"SQL Server", "PostgreSQL"}:
        return "eligible"
    if driver_family == "SQL Anywhere":
        return "blocked (lease/direct path)"
    return "unknown"


def get_driver_tuning_recommendation(driver_family: str) -> str:
    recommendations = {
        "SQL Server": (
            "Validate native/adaptive pool with driver matrix; tune ODBC_POOL_SIZE and "
            "SQL_QUEUE_MAX_WORKERS together, then watch transactional_native_pool_fallback."
        ),
        "PostgreSQL": (
            "Validate native/adaptive pool with driver matrix; prefer batched streaming "
            "for large SELECTs and watch pending saturation."
        ),
        "SQL Anywhere": (
            "Keep lease/direct path; tune SQL queue, direct limiter and bulkInsert "
            "instead of native pool."
        ),
    }
    return recommendations.get(
        driver_family,
        "Configure a representative DSN and run the driver matrix before changing pool defaults.",
    )


def update_context_from_health_snapshot_template(
    context: dict[str, str],
    template_path: Path,
) -> None:
    if not template_path.is_file():
        return

    try:
        snapshot = json.loads(template_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        Console.warn("Could not parse health snapshot template for effective tuning.")
        return

    runtime = snapshot.get("odbc_runtime_tuning") or {}
    for key, context_key in (
        ("pool_size", "OdbcPoolSize"),
        ("async_worker_count", "OdbcAsyncWorkerCount"),
        ("async_max_pending_requests", "OdbcAsyncMaxPendingRequests"),
        ("result_encoding", "OdbcResultEncoding"),
    ):
        value = runtime.get(key)
        if value is not None:
            context[context_key] = str(value)

    sql_queue = snapshot.get("sql_queue") or {}
    for key, context_key in (
        ("max_size", "SqlQueueMaxSize"),
        ("max_workers", "SqlQueueMaxWorkers"),
        ("enqueue_timeout_seconds", "SqlQueueTimeoutSec"),
    ):
        value = sql_queue.get(key)
        if value is not None:
            context[context_key] = str(value)

    pool = snapshot.get("pool") or {}
    acquire_timeout = pool.get("acquire_timeout_seconds")
    if acquire_timeout is not None:
        context["PoolAcquireTimeoutSec"] = str(acquire_timeout)


def get_long_query_for_driver(driver_family: str) -> str:
    key_groups = {
        "SQL Anywhere": (
            "ODBC_INTEGRATION_LONG_QUERY_SQL_ANYWHERE",
            "ODBC_INTEGRATION_LONG_QUERY",
        ),
        "SQL Server": (
            "ODBC_INTEGRATION_LONG_QUERY_SQL_SERVER",
            "ODBC_INTEGRATION_LONG_QUERY",
        ),
        "PostgreSQL": (
            "ODBC_INTEGRATION_LONG_QUERY_POSTGRESQL",
            "ODBC_INTEGRATION_LONG_QUERY",
        ),
    }
    return get_effective_env_value(key_groups.get(driver_family, ("ODBC_INTEGRATION_LONG_QUERY",)))


def resolve_benchmark_package(benchmark_path: Path) -> tuple[Path, Path, str]:
    resolved = benchmark_path.resolve(strict=True)
    package_root = resolved.parent.parent
    relative_path = f"example/{resolved.name}"
    return package_root, resolved, relative_path


def forward_script_args(argv: list[str], *, skip_help: bool = True) -> list[str]:
    if skip_help and "--help" in argv:
        return []
    return [arg for arg in argv if arg != "--"]


def exit_with(code: int) -> None:
    raise SystemExit(code)
