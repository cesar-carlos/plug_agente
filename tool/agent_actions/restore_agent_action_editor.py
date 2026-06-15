import re
import subprocess
from pathlib import Path

out_path = Path("lib/presentation/pages/agent_actions/agent_actions_page_editor.dart")

header = """import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/widgets.dart' as widgets;
import 'package:intl/intl.dart';
import 'package:plug_agente/application/actions/actions.dart';
import 'package:plug_agente/application/actions/agent_operational_profile_resolver.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/core/utils/powershell_command_line.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_widgets.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_confirmations.dart';
import 'package:plug_agente/shared/widgets/common/feedback/message_modal.dart';
import 'package:plug_agente/shared/widgets/common/form/app_dropdown.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';

"""

body = subprocess.check_output(
    ["git", "show", "HEAD:lib/presentation/pages/agent_actions/agent_actions_page_editor.dart"],
    text=True,
    encoding="utf-8",
)
if body.startswith("part of"):
    body = body.split("\n", 1)[1]

replacements = [
    ("abstract final class _AgentActionEditorKeys", "abstract final class AgentActionEditorKeys"),
    ("_AgentActionEditorKeys.", "AgentActionEditorKeys."),
    ("class _AgentActionEditor extends StatefulWidget", "class AgentActionEditor extends StatefulWidget"),
    ("const _AgentActionEditor({", "const AgentActionEditor({"),
    ("State<_AgentActionEditor> createState()", "State<AgentActionEditor> createState()"),
    (
        "class _AgentActionEditorState extends State<_AgentActionEditor>",
        "class _AgentActionEditorState extends State<AgentActionEditor>",
    ),
    ("void didUpdateWidget(_AgentActionEditor oldWidget)", "void didUpdateWidget(AgentActionEditor oldWidget)"),
    ("_HelpCheckboxLabel(", "AgentActionEditorHelpCheckboxLabel("),
    ("_PathPickerButton(", "AgentActionEditorPathPickerButton("),
    ("_DeveloperPathShortcuts(", "AgentActionEditorDeveloperPathShortcuts("),
    ("_DeveloperHintData", "AgentActionEditorDeveloperHintData"),
    ("_DeveloperHintsWrap(", "AgentActionEditorDeveloperHintsWrap("),
    ("_stateLabel(", "agentActionEditorStateLabel("),
    ("_AgentActionsPageKeys.", "AgentActionEditorKeys."),
]
for old, new in replacements:
    body = body.replace(old, new)

body = re.sub(
    r"\nclass _HelpCheckboxLabel extends StatelessWidget \{.*",
    "",
    body,
    flags=re.DOTALL,
)

body = body.replace(
    "String _typeLabel(AgentActionType type, AppLocalizations l10n) {\n"
    "  return switch (type) {\n"
    "    AgentActionType.commandLine => l10n.agentActionsTypeCommandLine,\n"
    "    AgentActionType.executable => l10n.agentActionsTypeExecutable,\n"
    "    AgentActionType.script => l10n.agentActionsTypeScript,\n"
    "    AgentActionType.jar => l10n.agentActionsTypeJar,\n"
    "    AgentActionType.email => l10n.agentActionsTypeEmail,\n"
    "    AgentActionType.comObject => l10n.agentActionsTypeComObject,\n"
    "    AgentActionType.developer => l10n.agentActionsTypeDeveloper,\n"
    "  };\n"
    "}\n\n",
    "",
)

body = body.replace("_typeLabel(", "agentActionEditorTypeLabel(")

keys_block = """abstract final class AgentActionEditorKeys {
  static const ValueKey<String> actionTypeDropdown = ValueKey<String>('agent_action_editor_type_dropdown');
  static const ValueKey<String> powerShellModeDropdown = ValueKey<String>(
    'agent_action_editor_powershell_mode_dropdown',
  );
  static const ValueKey<String> powerShellExecutableDropdown = ValueKey<String>(
    'agent_action_editor_powershell_executable_dropdown',
  );
  static const ValueKey<String> remoteReapprovalInfoBar = ValueKey<String>('agent_actions_remote_reapproval_info_bar');
  static const ValueKey<String> developerConnectionMissingInfoBar = ValueKey<String>(
    'agent_actions_developer_connection_missing_info_bar',
  );
  static const ValueKey<String> developerConnectionUnknownInfoBar = ValueKey<String>(
    'agent_actions_developer_connection_unknown_info_bar',
  );
  static const ValueKey<String> developerConnectionChangedInfoBar = ValueKey<String>(
    'agent_actions_developer_connection_changed_info_bar',
  );
}"""

body = re.sub(
    r"abstract final class AgentActionEditorKeys \{.*?\n\}",
    keys_block,
    body,
    count=1,
    flags=re.DOTALL,
)

if "const List<_AgentActionDraftKind> _editableDraftKinds" not in body:
    editable = """
const List<_AgentActionDraftKind> _editableDraftKinds = <_AgentActionDraftKind>[
  _AgentActionDraftKind.commandLine,
  _AgentActionDraftKind.executable,
  _AgentActionDraftKind.script,
  _AgentActionDraftKind.jar,
  _AgentActionDraftKind.email,
  _AgentActionDraftKind.comObject,
  _AgentActionDraftKind.developer,
  _AgentActionDraftKind.powerShell,
];

"""
    body = body.replace(
        "class _AgentActionEditorState extends State<AgentActionEditor> {",
        editable + "class _AgentActionEditorState extends State<AgentActionEditor> {",
    )

if "_draftKindLabel(" not in body:
    draft_kind_label = """
  String _draftKindLabel(_AgentActionDraftKind draftKind) {
    return switch (draftKind) {
      _AgentActionDraftKind.commandLine => agentActionEditorTypeLabel(AgentActionType.commandLine, widget.l10n),
      _AgentActionDraftKind.executable => agentActionEditorTypeLabel(AgentActionType.executable, widget.l10n),
      _AgentActionDraftKind.script => agentActionEditorTypeLabel(AgentActionType.script, widget.l10n),
      _AgentActionDraftKind.jar => agentActionEditorTypeLabel(AgentActionType.jar, widget.l10n),
      _AgentActionDraftKind.email => agentActionEditorTypeLabel(AgentActionType.email, widget.l10n),
      _AgentActionDraftKind.comObject => agentActionEditorTypeLabel(AgentActionType.comObject, widget.l10n),
      _AgentActionDraftKind.developer => agentActionEditorTypeLabel(AgentActionType.developer, widget.l10n),
      _AgentActionDraftKind.powerShell => widget.l10n.agentActionsTypePowerShell,
    };
  }

"""
    body = body.replace(
        "  String _powerShellExecutableName(_PowerShellExecutable executable) {",
        draft_kind_label + "  String _powerShellExecutableName(_PowerShellExecutable executable) {",
    )
    body = body.replace(
        "agentActionEditorTypeLabel(_draftKind, widget.l10n)",
        "_draftKindLabel(_draftKind)",
    )

out_path.write_text(header + body.lstrip("\n"), encoding="utf-8", newline="\n")
print(f"Wrote {len((header + body).splitlines())} lines to {out_path}")

# Sanity check before finishing.
restored = out_path.read_text(encoding="utf-8")
if "part '" in restored:
    raise SystemExit("Restore produced part directives; aborting.")
if restored.count("class AgentActionEditor extends") != 1:
    raise SystemExit("Restore produced duplicate AgentActionEditor declarations; aborting.")
if len(restored.splitlines()) < 3000:
    raise SystemExit(f"Restore output too short ({len(restored.splitlines())} lines); aborting.")
