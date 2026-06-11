#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SRC_PATH = PROJECT_ROOT / "lib" / "presentation" / "pages" / "agent_actions" / "agent_actions_page_editor.dart"
EDITOR_DIR = PROJECT_ROOT / "lib" / "presentation" / "pages" / "agent_actions" / "widgets" / "editor"


def find_line(lines: list[str], pattern: str) -> int:
    regex = re.compile(pattern)
    for index, line in enumerate(lines):
        if regex.search(line):
            return index + 1
    raise ValueError(f"Pattern not found: {pattern}")


def get_lines(lines: list[str], start: int, end: int) -> list[str]:
    if end < start:
        return []
    return lines[start - 1 : end]


def wrap_mixin(name: str, body_lines: list[str]) -> list[str]:
    return [
        "part of '../../agent_actions_page_editor.dart';",
        "",
        f"mixin {name} on _AgentActionEditorStateBase {{",
        *body_lines,
        "}",
    ]


def main() -> int:
    EDITOR_DIR.mkdir(parents=True, exist_ok=True)
    lines = SRC_PATH.read_text(encoding="utf-8").splitlines()

    import_end_line = 0
    for index, line in enumerate(lines):
        if line.startswith("import "):
            import_end_line = index + 1

    state_line = find_line(lines, r"^class _AgentActionEditorState extends")
    init_line = find_line(lines, r"^\s+void initState\(\)")
    fields_start_line = state_line + 1
    fields_end_line = init_line - 1
    while fields_end_line > fields_start_line and not lines[fields_end_line - 1].strip():
        fields_end_line -= 1

    preflight_line = find_line(lines, r"^\s+Widget _buildPreflightGateInfoBar")
    exec_policies_line = find_line(lines, r"^\s+Widget _buildExecutionPoliciesSection")
    draft_fields_line = find_line(lines, r"^\s+List<Widget> _buildDraftFields")
    dev_hints_line = find_line(lines, r"^\s+List<Widget> _buildDeveloperBinaryPathHints")
    save_exec_line = find_line(lines, r"^\s+Future<bool> _saveExecutableDraft")
    schedule_dev_line = find_line(lines, r"^\s+void _scheduleDeveloperConnectionReload")

    close_state_line = len(lines)
    for index in range(len(lines) - 1, -1, -1):
        if lines[index] == "}":
            close_state_line = index + 1
            break

    field_body = get_lines(lines, fields_start_line, fields_end_line)
    main_lines = (
        get_lines(lines, 1, import_end_line)
        + [
            "",
            "part 'widgets/editor/agent_action_editor_core.dart';",
            "part 'widgets/editor/agent_action_editor_ui.dart';",
            "part 'widgets/editor/agent_action_editor_policies.dart';",
            "part 'widgets/editor/agent_action_editor_draft_fields.dart';",
            "part 'widgets/editor/agent_action_editor_developer.dart';",
            "part 'widgets/editor/agent_action_editor_save.dart';",
            "",
        ]
        + get_lines(lines, import_end_line + 1, state_line - 1)
        + [
            "",
            "abstract class _AgentActionEditorStateBase extends State<AgentActionEditor> {",
        ]
        + field_body
        + [
            "}",
            "",
            "class _AgentActionEditorState extends _AgentActionEditorStateBase",
            "    with",
            "        _AgentActionEditorCore,",
            "        _AgentActionEditorUi,",
            "        _AgentActionEditorPolicies,",
            "        _AgentActionEditorDraftFields,",
            "        _AgentActionEditorDeveloper,",
            "        _AgentActionEditorSave {}",
            "",
        ]
    )

    SRC_PATH.write_text("\n".join(main_lines) + "\n", encoding="utf-8")

    core_body = get_lines(lines, init_line, preflight_line - 1)
    if core_body and re.match(r"^\s+void initState", core_body[0]):
        core_body[0] = "  @override\n" + core_body[0]

    parts = {
        "agent_action_editor_core.dart": wrap_mixin("_AgentActionEditorCore", core_body),
        "agent_action_editor_ui.dart": wrap_mixin(
            "_AgentActionEditorUi",
            get_lines(lines, preflight_line, exec_policies_line - 1),
        ),
        "agent_action_editor_policies.dart": wrap_mixin(
            "_AgentActionEditorPolicies",
            get_lines(lines, exec_policies_line, draft_fields_line - 1),
        ),
        "agent_action_editor_draft_fields.dart": wrap_mixin(
            "_AgentActionEditorDraftFields",
            get_lines(lines, draft_fields_line, dev_hints_line - 1),
        ),
        "agent_action_editor_developer.dart": wrap_mixin(
            "_AgentActionEditorDeveloper",
            get_lines(lines, dev_hints_line, save_exec_line - 1)
            + get_lines(lines, schedule_dev_line, close_state_line - 1),
        ),
        "agent_action_editor_save.dart": wrap_mixin(
            "_AgentActionEditorSave",
            get_lines(lines, save_exec_line, schedule_dev_line - 1),
        ),
    }

    for file_name, content in parts.items():
        (EDITOR_DIR / file_name).write_text("\n".join(content) + "\n", encoding="utf-8")

    print(f"Main lines: {len(main_lines)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
