import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_file_picker.dart';

class AgentActionEditorPathPickCoordinator {
  const AgentActionEditorPathPickCoordinator({
    required this.draft,
    required this.l10n,
    required this.filePicker,
    required this.isMounted,
    required this.onValidationMessage,
    required this.onPathApplied,
  });

  final AgentActionDraft draft;
  final AppLocalizations l10n;
  final AgentActionFilePicker filePicker;
  final bool Function() isMounted;
  final void Function(String message) onValidationMessage;
  final void Function(void Function() applyPath) onPathApplied;

  Future<void> pickJarPath() => _pickAndApply(
    dialogTitle: l10n.agentActionsFormBrowseJarPath,
    allowedExtensions: const ['jar'],
    apply: (path) => draft.jar.path.text = path,
  );

  Future<void> pickJavaExecutablePath() => _pickAndApply(
    dialogTitle: l10n.agentActionsFormBrowseJavaExecutablePath,
    allowedExtensions: const ['exe'],
    apply: (path) => draft.jar.javaExecutablePath.text = path,
  );

  Future<void> pickScriptPath() => _pickAndApply(
    dialogTitle: l10n.agentActionsFormBrowseScriptPath,
    allowedExtensions: const ['ps1', 'bat', 'cmd', 'py'],
    apply: (path) => draft.script.path.text = path,
  );

  Future<void> pickPowerShellScriptPath() => _pickAndApply(
    dialogTitle: l10n.agentActionsFormBrowsePowerShellScriptPath,
    allowedExtensions: const ['ps1'],
    apply: (path) => draft.script.path.text = path,
  );

  Future<void> pickScriptInterpreterPath() => _pickAndApply(
    dialogTitle: l10n.agentActionsFormBrowseInterpreterPath,
    allowedExtensions: const ['exe'],
    apply: (path) => draft.script.interpreterPath.text = path,
  );

  Future<void> pickExecutableTargetPath() => _pickAndApply(
    dialogTitle: l10n.agentActionsFormBrowseExecutablePath,
    allowedExtensions: const ['exe', 'bat', 'cmd'],
    apply: (path) => draft.executable.targetPath.text = path,
  );

  Future<void> _pickAndApply({
    required String dialogTitle,
    required List<String> allowedExtensions,
    required void Function(String selectedPath) apply,
    Future<void> Function()? onAfter,
  }) async {
    final String? selectedPath;
    try {
      selectedPath = await filePicker.pickSingleFile(
        dialogTitle: dialogTitle,
        allowedExtensions: allowedExtensions,
      );
    } on Exception {
      if (!isMounted()) {
        return;
      }
      onValidationMessage(l10n.agentActionsFormBrowseFileError);
      return;
    }
    if (selectedPath == null || !isMounted()) {
      return;
    }

    onPathApplied(() => apply(selectedPath!));

    if (onAfter != null) {
      await onAfter();
    }
  }
}
