"""Validates local CI configuration before expensive workflow jobs start."""

from __future__ import annotations

import argparse
import importlib.util
import re
import sys
from collections.abc import Iterable
from pathlib import Path


_UNITTEST_COMMAND = re.compile(r"\bpython3?\s+-m\s+unittest\s+([^\r\n]+)")
_UNITTEST_MODULE = re.compile(r"\btool(?:\.[A-Za-z_]\w*)+\b")
_LINE_CONTINUATION = re.compile(r"\\\s*(?:\r?\n)")
_ANALYZER_PLUGIN = re.compile(r"^\s*plugins\s*:\s*$", re.MULTILINE)

_WORKFLOW_DIRECTORY = Path(".github/workflows")


def collect_unittest_modules(workflow_source: str) -> list[str]:
    """Returns Python test modules referenced by unittest commands."""
    normalized_source = _LINE_CONTINUATION.sub(" ", workflow_source)
    modules: list[str] = []
    for command in _UNITTEST_COMMAND.findall(normalized_source):
        modules.extend(_UNITTEST_MODULE.findall(command))
    return modules


def validate_analysis_options(analysis_options: str) -> list[str]:
    """Reports deprecated analyzer configuration that fails current Flutter CI."""
    if _ANALYZER_PLUGIN.search(analysis_options):
        return [
            "analysis_options.yaml uses deprecated analyzer plugins. "
            "Use build_runner for code generation instead.",
        ]
    return []


def validate_configuration(repo_root: Path) -> list[str]:
    """Validates workflow test-module references and analyzer configuration."""
    errors: list[str] = []
    sys.path.insert(0, str(repo_root))

    workflow_directory = repo_root / _WORKFLOW_DIRECTORY
    workflow_paths = sorted(workflow_directory.glob("*.y*ml")) if workflow_directory.is_dir() else []
    if not workflow_paths:
        errors.append(f"Workflow directory is missing or empty: {_WORKFLOW_DIRECTORY}")

    for workflow_path in workflow_paths:
        relative_path = workflow_path.relative_to(repo_root)

        for module in collect_unittest_modules(workflow_path.read_text(encoding="utf-8")):
            if importlib.util.find_spec(module) is None:
                errors.append(f"{relative_path} references unavailable Python module: {module}")

    analysis_options_path = repo_root / "analysis_options.yaml"
    if not analysis_options_path.is_file():
        errors.append("analysis_options.yaml is missing")
    else:
        errors.extend(validate_analysis_options(analysis_options_path.read_text(encoding="utf-8")))

    return errors


def main(arguments: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path(__file__).resolve().parents[2],
        help="Repository root to validate.",
    )
    parsed = parser.parse_args(arguments)
    errors = validate_configuration(parsed.repo_root.resolve())
    if not errors:
        print("CI configuration is valid.")
        return 0

    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
