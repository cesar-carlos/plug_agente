import 'package:flutter/widgets.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/feedback/app_confirm_dialog.dart';

Future<bool> confirmReapproveRemoteAgentAction({
  required BuildContext context,
  required AppLocalizations l10n,
}) {
  return _confirm(
    context: context,
    title: l10n.agentActionsConfirmRemoteReapprovalTitle,
    message: l10n.agentActionsConfirmRemoteReapprovalMessage,
    confirmLabel: l10n.agentActionsConfirmRemoteReapprovalConfirm,
    cancelLabel: l10n.agentActionsConfirmRemoteReapprovalCancel,
  );
}

Future<bool> confirmEnableRemoteAgentAction({
  required BuildContext context,
  required AppLocalizations l10n,
}) {
  return _confirm(
    context: context,
    title: l10n.agentActionsConfirmRemoteTitle,
    message: l10n.agentActionsConfirmRemoteMessage,
    confirmLabel: l10n.agentActionsConfirmRemoteConfirm,
    cancelLabel: l10n.agentActionsConfirmRemoteCancel,
  );
}

Future<bool> confirmEnableRemoteAdHocAgentAction({
  required BuildContext context,
  required AppLocalizations l10n,
}) {
  return _confirm(
    context: context,
    title: l10n.agentActionsConfirmRemoteAdHocTitle,
    message: l10n.agentActionsConfirmRemoteAdHocMessage,
    confirmLabel: l10n.agentActionsConfirmRemoteAdHocConfirm,
    cancelLabel: l10n.agentActionsConfirmRemoteAdHocCancel,
  );
}

Future<bool> confirmAppCloseTrigger({
  required BuildContext context,
  required AppLocalizations l10n,
}) {
  return _confirm(
    context: context,
    title: l10n.agentActionsConfirmAppCloseTriggerTitle,
    message: l10n.agentActionsConfirmAppCloseTriggerMessage,
    confirmLabel: l10n.agentActionsConfirmAppCloseTriggerConfirm,
    cancelLabel: l10n.agentActionsConfirmAppCloseTriggerCancel,
  );
}

Future<bool> confirmImportAgentActionsBundle({
  required BuildContext context,
  required AppLocalizations l10n,
}) {
  return _confirm(
    context: context,
    title: l10n.agentActionsConfirmImportBundleTitle,
    message: l10n.agentActionsConfirmImportBundleMessage,
    confirmLabel: l10n.agentActionsConfirmImportBundleConfirm,
    cancelLabel: l10n.agentActionsConfirmImportBundleCancel,
  );
}

Future<bool> confirmEnableElevatedAgentAction({
  required BuildContext context,
  required AppLocalizations l10n,
}) {
  return _confirm(
    context: context,
    title: l10n.agentActionsConfirmElevatedTitle,
    message: l10n.agentActionsConfirmElevatedMessage,
    confirmLabel: l10n.agentActionsConfirmElevatedConfirm,
    cancelLabel: l10n.agentActionsConfirmElevatedCancel,
  );
}

Future<bool> confirmDangerousCommandRun({
  required BuildContext context,
  required AppLocalizations l10n,
  required String patternId,
  required String patternDescription,
}) {
  return _confirm(
    context: context,
    title: l10n.agentActionsConfirmDangerousCommandTitle,
    message: l10n.agentActionsConfirmDangerousCommandMessage(
      patternId,
      patternDescription,
    ),
    confirmLabel: l10n.agentActionsConfirmDangerousCommandConfirm,
    cancelLabel: l10n.agentActionsConfirmDangerousCommandCancel,
  );
}

Future<bool> _confirm({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  required String cancelLabel,
}) {
  return AppConfirmDialog.show(
    context: context,
    title: title,
    message: message,
    confirmLabel: confirmLabel,
    cancelLabel: cancelLabel,
  );
}
