"""Bootstrap sys.path for scripts under tool/<category>/."""

from __future__ import annotations

import sys
from pathlib import Path


def bootstrap_category_script(script_file: str | Path) -> tuple[Path, Path]:
    """Add project root and tool/ to sys.path for category entrypoints."""
    path = Path(script_file).resolve()
    tool_dir: Path | None = None
    for parent in path.parents:
        if (parent / "py" / "script_utils.py").is_file():
            tool_dir = parent
            break
    if tool_dir is None:
        raise RuntimeError(f"Could not locate tool directory from {path}")

    project_root = tool_dir.parent
    for entry in (str(project_root), str(tool_dir)):
        if entry not in sys.path:
            sys.path.insert(0, entry)
    return project_root, tool_dir
