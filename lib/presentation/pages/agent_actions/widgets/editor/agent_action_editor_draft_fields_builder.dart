import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_kind.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_developer_editor_section.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_draft_field_groups.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_keys.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_sections.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_file_picker.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';

class AgentActionEditorDraftFieldsBuilder {
  const AgentActionEditorDraftFieldsBuilder({
    required this.l10n,
    required this.provider,
    required this.draft,
    required this.definition,
    required this.enabled,
    required this.filePicker,
    required this.showInlineFeedback,
    required this.onSave,
    required this.onValidationMessageChanged,
    required this.onReloadConnections,
    required this.onDialogWarning,
    required this.onPickExecutableTargetPath,
    required this.onPickJarPath,
    required this.onPickJavaExecutablePath,
    required this.onPickScriptPath,
    required this.onPickScriptInterpreterPath,
    required this.onPickPowerShellScriptPath,
    required this.isPowerShellModeUnavailable,
    required this.onPowerShellModeChanged,
    required this.onPowerShellExecutableChanged,
  });

  final AppLocalizations l10n;
  final AgentActionsProvider provider;
  final AgentActionDraft draft;
  final AgentActionDefinition? definition;
  final bool enabled;
  final AgentActionFilePicker filePicker;
  final bool showInlineFeedback;
  final VoidCallback onSave;
  final ValueChanged<String?> onValidationMessageChanged;
  final Future<void> Function({
    required AgentActionPathPolicy pathPolicy,
    String? selectedConnectionId,
  }) onReloadConnections;
  final void Function(AgentActionEditorDialogWarning warning)? onDialogWarning;
  final Future<void> Function() onPickExecutableTargetPath;
  final Future<void> Function() onPickJarPath;
  final Future<void> Function() onPickJavaExecutablePath;
  final Future<void> Function() onPickScriptPath;
  final Future<void> Function() onPickScriptInterpreterPath;
  final Future<void> Function() onPickPowerShellScriptPath;
  final bool Function(PowerShellDraftMode mode) isPowerShellModeUnavailable;
  final ValueChanged<PowerShellDraftMode> onPowerShellModeChanged;
  final ValueChanged<PowerShellExecutable> onPowerShellExecutableChanged;

  List<Widget> build(bool saving) {
    if (draft.draftKind == AgentActionDraftKind.powerShell) {
      return _buildPowerShellFields(saving);
    }

    final fieldsEnabled = enabled && !saving && provider.canSaveAction;
    return switch (draft.draftType) {
      AgentActionType.commandLine => <Widget>[
        AgentActionCommandLineFields(
          l10n: l10n,
          enabled: fieldsEnabled,
          commandController: draft.commandLine.command,
          workingDirectoryController: draft.commandLine.workingDirectory,
          onSubmitted: onSave,
        ),
      ],
      AgentActionType.executable => <Widget>[
        AgentActionExecutableFields(
          l10n: l10n,
          enabled: fieldsEnabled,
          executableTargetPathController: draft.executable.targetPath,
          argumentsController: draft.executable.arguments,
          workingDirectoryController: draft.commandLine.workingDirectory,
          onPickExecutablePath: onPickExecutableTargetPath,
          onSubmitted: onSave,
        ),
      ],
      AgentActionType.comObject => <Widget>[
        AgentActionComObjectFields(
          l10n: l10n,
          enabled: fieldsEnabled,
          comProgIdController: draft.comObject.progId,
          comMemberNameController: draft.comObject.memberName,
          comArgumentsController: draft.comObject.arguments,
          onSubmitted: onSave,
        ),
      ],
      AgentActionType.email => <Widget>[
        AgentActionEmailFields(
          l10n: l10n,
          enabled: fieldsEnabled,
          smtpProfileIdController: draft.email.smtpProfileId,
          fromController: draft.email.from,
          toController: draft.email.to,
          ccController: draft.email.cc,
          bccController: draft.email.bcc,
          subjectController: draft.email.subject,
          bodyController: draft.email.body,
          attachmentsController: draft.email.attachments,
          onSubmitted: onSave,
        ),
      ],
      AgentActionType.jar => <Widget>[
        AgentActionJarFields(
          l10n: l10n,
          enabled: fieldsEnabled,
          jarPathController: draft.jar.path,
          javaExecutablePathController: draft.jar.javaExecutablePath,
          argumentsController: draft.executable.arguments,
          workingDirectoryController: draft.commandLine.workingDirectory,
          onPickJarPath: onPickJarPath,
          onPickJavaExecutablePath: onPickJavaExecutablePath,
          onSubmitted: onSave,
        ),
      ],
      AgentActionType.script => <Widget>[
        AgentActionScriptFields(
          l10n: l10n,
          enabled: fieldsEnabled,
          scriptPathController: draft.script.path,
          interpreterPathController: draft.script.interpreterPath,
          argumentsController: draft.executable.arguments,
          workingDirectoryController: draft.commandLine.workingDirectory,
          onPickScriptPath: onPickScriptPath,
          onPickInterpreterPath: onPickScriptInterpreterPath,
          onSubmitted: onSave,
        ),
      ],
      AgentActionType.developer => <Widget>[
        AgentActionDeveloperEditorSection(
          provider: provider,
          l10n: l10n,
          draft: draft,
          definition: definition,
          enabled: fieldsEnabled,
          filePicker: filePicker,
          onSave: onSave,
          onValidationMessageChanged: onValidationMessageChanged,
          onReloadConnections: onReloadConnections,
          showInlineFeedback: showInlineFeedback,
          onDialogWarning: onDialogWarning,
        ),
      ],
    };
  }

  List<Widget> _buildPowerShellFields(bool saving) {
    final fieldsEnabled = !saving && provider.canSaveAction;
    return <Widget>[
      AgentActionPowerShellDraftFields(
        l10n: l10n,
        enabled: fieldsEnabled,
        modeDisplayEnabled: !saving,
        isEditing: draft.editingActionId != null,
        mode: draft.powerShellMode,
        executable: draft.powerShellExecutable,
        isModeUnavailable: isPowerShellModeUnavailable,
        modeDisplayController: draft.displayBindings.powerShellModeDisplay,
        commandController: draft.commandLine.command,
        scriptPathController: draft.script.path,
        argumentsController: draft.executable.arguments,
        workingDirectoryController: draft.commandLine.workingDirectory,
        modeDropdownKey: AgentActionEditorKeys.powerShellModeDropdown,
        executableDropdownKey: AgentActionEditorKeys.powerShellExecutableDropdown,
        onModeChanged: onPowerShellModeChanged,
        onExecutableChanged: onPowerShellExecutableChanged,
        onPickScriptPath: onPickPowerShellScriptPath,
        onSubmitted: onSave,
      ),
    ];
  }
}
