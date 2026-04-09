"""Merge tool/l10n_merge_data.json into lib/l10n/app_en.arb and app_pt.arb."""

from __future__ import annotations

import json
from pathlib import Path


def main() -> None:
    root = Path(__file__).resolve().parent.parent
    merge_path = root / "tool" / "l10n_merge_data.json"
    raw = json.loads(merge_path.read_text(encoding="utf-8"))
    additions_en: dict[str, object] = raw["en"]
    additions_pt: dict[str, object] = raw["pt"]

    for name, additions in (("app_en.arb", additions_en), ("app_pt.arb", additions_pt)):
        path = root / "lib" / "l10n" / name
        data = json.loads(path.read_text(encoding="utf-8"))
        for key, value in additions.items():
            data[key] = value
        path.write_text(
            json.dumps(data, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )


if __name__ == "__main__":
    main()
